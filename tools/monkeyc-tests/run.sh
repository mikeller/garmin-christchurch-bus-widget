#!/usr/bin/env bash
# Build and (optionally) test tracked sources in a disposable staging tree.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
sdk="${CONNECT_IQ_SDK:-}"
simulator_cmd=""
simulator_port=1234
startup=40
run_timeout=180
compile_only=false
output=""
devices=()
while (($#)); do
    case "$1" in
        --sdk|--simulator-cmd|--simulator-port|--startup-timeout|--run-timeout|--output)
            (($# >= 2)) || { echo "missing value for $1" >&2; exit 2; }
            case "$1" in
                --sdk) sdk=$2 ;;
                --simulator-cmd) simulator_cmd=$2 ;;
                --simulator-port) simulator_port=$2 ;;
                --startup-timeout) startup=$2 ;;
                --run-timeout) run_timeout=$2 ;;
                --output) output=$2 ;;
            esac
            shift 2 ;;
        --compile-only) compile_only=true; shift ;;
        --) shift; devices+=("$@"); break ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) devices+=("$1"); shift ;;
    esac
done
((${#devices[@]})) || devices=(descentmk1 fr645m fenix5plus fenix5)
[[ $startup =~ ^[1-9][0-9]*$ && $run_timeout =~ ^[1-9][0-9]*$ ]] || {
    echo "timeouts must be positive integer seconds" >&2; exit 2;
}
if [[ ! $simulator_port =~ ^[1-9][0-9]*$ ]] || (( simulator_port > 65535 )); then
    echo "simulator port must be 1..65535" >&2; exit 2;
fi
for cmd in python3 git openssl timeout flock nc; do
    command -v "$cmd" >/dev/null || { echo "missing prerequisite: $cmd" >&2; exit 2; }
done
if [[ -z $sdk ]]; then
    if ! command -v monkeyc >/dev/null || ! command -v monkeydo >/dev/null; then
        echo "set --sdk /path/to/ConnectIQ/SDK (or put monkeyc and monkeydo on PATH)" >&2; exit 2;
    fi
    sdk="$(cd -- "$(dirname -- "$(command -v monkeyc)")/.." && pwd -P)"
fi
sdk="$(cd -- "$sdk" && pwd -P)" || { echo "SDK directory not found" >&2; exit 2; }
bin="$sdk/bin"
for cmd in monkeyc monkeydo; do
    [[ -x $bin/$cmd ]] || { echo "missing SDK command: $bin/$cmd" >&2; exit 2; }
done
if [[ -z $simulator_cmd ]]; then simulator_cmd="$bin/simulator"; fi
if [[ $compile_only == false && ! -x $simulator_cmd ]]; then
    echo "simulator command must be an executable path: $simulator_cmd" >&2; exit 2
fi
devices_dir="${CONNECT_IQ_DEVICES:-$HOME/.Garmin/ConnectIQ/Devices}"
[[ -d $devices_dir ]] || { echo "official device definitions missing: $devices_dir" >&2; exit 2; }
mapfile -t qualifiers < <(python3 - "$root/monkey.jungle" <<'PY'
import re
import sys
for qualifier in sorted(set(re.findall(r"(?m)^([a-zA-Z0-9]+)\.(?:excludeAnnotations|resourcePath)\s*=", open(sys.argv[1]).read()))):
    print(qualifier)
PY
)
for device in "${devices[@]}" "${qualifiers[@]}"; do
    [[ $device != base ]] || continue
    [[ $device =~ ^[a-zA-Z0-9]+$ ]] || { echo "invalid device: $device" >&2; exit 2; }
    [[ -d $devices_dir/$device ]] || {
        echo "missing official definition for $device in $devices_dir (selected device or jungle qualifier)" >&2; exit 2;
    }
done
for device in "${devices[@]}"; do
    grep -Fq "id=\"$device\"" "$root/manifest.xml" || {
        echo "device $device not listed in manifest.xml" >&2; exit 2;
    }
done
lock="${TMPDIR:-/tmp}/connectiq-monkeyc-tests-$(id -u).lock"
exec 9>"$lock"
flock -n 9 || { echo "another simulator-test run holds $lock" >&2; exit 2; }
work="$(mktemp -d)"
sim_pid=""
cleanup() {
    if [[ -n $sim_pid ]]; then
        kill -- "-$sim_pid" 2>/dev/null || :
        wait "$sim_pid" 2>/dev/null || :
    fi
    rm -rf -- "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$work/stage" "$work/logs"
chmod 700 "$work"
python3 "$root/tools/monkeyc-tests/stage.py" "$root" "$work/stage"
key="$work/key.der"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>"$work/logs/openssl.log" |
    openssl pkcs8 -topk8 -nocrypt -outform DER -out "$key"
chmod 600 "$key"
version="$("$bin/monkeyc" -v)"
revision="$(git -C "$root" rev-parse --short HEAD)"
echo "SDK: $sdk ($version); source: $revision (tracked files from this checkout)"
if [[ -n $output ]]; then
    output="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$output")"
    [[ $output != "$root" && $output != "$root/"* && $output != "$work" && $output != "$work/"* ]] || {
        echo "output must be outside checkout and staging directory" >&2; exit 2;
    }
    mkdir -p -- "$output"
    logs="$output"
else
    logs="$work/logs"
fi
failed=0
ready=false
simulator_unavailable=false
for device in "${devices[@]}"; do
    prg="$work/$device-test.prg"
    echo "target=$device compile=RUNNING"
    if ! (cd "$work/stage" && "$bin/monkeyc" -d "$device" -f monkey.jungle -o "$prg" -y "$key" -t -w) >"$logs/$device.compile.log" 2>&1; then
        echo "target=$device compile=FAILED tests=NOT RUN (see $logs/$device.compile.log)"
        failed=1
        continue
    fi
    if [[ $compile_only == true ]]; then
        echo "target=$device compile=PASSED tests=NOT RUN (compile-only)"
        continue
    fi
    if [[ $simulator_unavailable == true ]]; then
        echo "target=$device compile=PASSED tests=NOT RUN (simulator unavailable)"
        continue
    fi
    if [[ $ready == false ]]; then
        if ! nc -z 127.0.0.1 "$simulator_port" 2>/dev/null; then
            [[ -n ${DISPLAY:-} ]] || {
                echo "no DISPLAY and no simulator on 127.0.0.1:$simulator_port" >&2
                failed=1; simulator_unavailable=true
            }
            if [[ $simulator_unavailable == false ]]; then
                setsid "$simulator_cmd" >"$logs/simulator.log" 2>&1 &
                sim_pid=$!
            fi
        fi
        deadline=$((SECONDS + startup))
        until [[ $simulator_unavailable == true ]] || nc -z 127.0.0.1 "$simulator_port" 2>/dev/null; do
            if [[ -n $sim_pid ]] && ! kill -0 "$sim_pid" 2>/dev/null; then
                echo "simulator exited (see $logs/simulator.log)" >&2; failed=1; simulator_unavailable=true; break
            fi
            if (( SECONDS >= deadline )); then
                echo "simulator readiness timeout at 127.0.0.1:$simulator_port" >&2; failed=1; simulator_unavailable=true; break
            fi
            sleep 1
        done
        if [[ $simulator_unavailable == true ]]; then
            echo "target=$device compile=PASSED tests=NOT RUN (simulator unavailable)"
            continue
        fi
        ready=true
    fi
    set +e
    timeout --signal=TERM --kill-after=5 "$run_timeout" "$bin/monkeydo" "$prg" "$device" -t >"$logs/$device.test.log" 2>&1
    rc=$?
    python3 "$root/tools/monkeyc-tests/parse.py" "$logs/$device.test.log" >"$work/result"
    parsed=$?
    set -e
    result="$(cat "$work/result")"
    if (( rc == 124 || rc == 137 || rc == 125 || rc == 126 || rc == 127 || parsed != 0 )); then
        echo "target=$device compile=PASSED tests=FAILED monkeydo_exit=$rc result=$result (see $logs/$device.test.log)"
        failed=1
    else
        echo "target=$device compile=PASSED tests=PASSED monkeydo_exit=$rc result=$result"
    fi
done
if (( failed )); then exit 1; fi
