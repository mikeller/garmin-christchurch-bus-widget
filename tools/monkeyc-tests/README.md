# Local Connect IQ tests (Linux)

Run these commands on an already provisioned graphical workstation. This is
not hosted CI and does not install or redistribute an SDK or device definitions.
Requirements: installed Garmin Connect IQ SDK and official device files in
`~/.Garmin/ConnectIQ/Devices`, Bash, Git, Python 3, OpenSSL, `timeout`,
`flock`, `nc`, and a working simulator display and libraries. The runner
preflights **all** device-qualified lines in the checkout's `monkey.jungle`,
including devices not selected on the command line. There are no credentials:
the staged SubscriptionKey is empty and successful Metro requests are not
required for the pure unit tests.

```sh
python3 -m unittest discover -s tools/monkeyc-tests -v
bash -n tools/monkeyc-tests/run.sh
shellcheck tools/monkeyc-tests/run.sh
SDK_BIN="$(connect-iq-sdk-manager sdk current-path --bin)"
SDK="${SDK_BIN%/bin}"
bash tools/monkeyc-tests/run.sh --sdk "$SDK" --compile-only
bash tools/monkeyc-tests/run.sh --sdk "$SDK" --output "$HOME/ciq-test-results"
bash tools/monkeyc-tests/run.sh --sdk "$SDK" --startup-timeout 60 \
  --run-timeout 240 descentmk1 fenix5
```

Commands work from any directory when the script path is absolute. The default
order is `descentmk1 fr645m fenix5plus fenix5`. `--sdk` accepts the SDK root,
not its `bin` directory; alternatively, place `monkeyc` and `monkeydo` from
one SDK on PATH. Both timeouts are positive integer seconds. `--compile-only`
prints `tests=NOT RUN`; it does not establish simulator coverage. Without
`--output`, logs, PRGs and the disposable signing key are removed on exit.
With `--output`, only diagnostic logs persist (not keys or PRGs). The script
copies tracked files from the checked-out working tree into a temporary stage;
untracked edits are not included. It excludes `resources/strings/secrets.xml`
**before copying**, checks the empty template and creates only that empty
resource in the stage. It never opens the source secrets file or uses an
existing developer key. The single per-invocation RSA key is PKCS#8 DER,
mode 0600, removed on exit/signals. The source checkout, build outputs,
Garmin preferences and installed SDK are not modified. Do not put the output
directory inside the checkout.

Tests are built with `monkeyc -t -w` for each selected device, then `monkeydo
<test.prg> <device> -t` runs sequentially. The last non-empty summary line
must be exactly `PASSED (passed=N, failed=0, errors=0)` with N positive.
Inspect per-device compile/test logs if any build or test fails. A non-zero
monkeydo exit after a valid pass is reported separately, not silently equated
with a failed test; timeout and launch errors always fail. Zero tests,
including tests excluded by device feature annotations, are a coverage gap,
not success. Changing app tests or feature exclusions is outside this work.
The runner takes an exclusive per-user local lock, checks the local simulator
TCP endpoint at `127.0.0.1:1234` (the port reported in Garmin simulator
troubleshooting discussions), reuses an already listening simulator, and
stops only a simulator it started. On failure check the simulator log for
missing display or libraries. The TCP check confirms connectivity only, not
that the listener is the expected simulator. `--simulator-port` overrides 1234
for fake-runner tests; normal `monkeydo` uses the SDK's own port.

## Ubuntu 26.10 graphical workstation

On this workstation the native SDK 9.3.0 simulator cannot load
`libwebkit2gtk-4.0`, `libsoup-2.4` and `libjavascriptcoregtk-4.0`.
This is version-specific evidence, not a general SDK guarantee. The human
reported a working Ubuntu 22.04 Podman simulator for SDK 9.3.0, with manual
`monkeydo -t` passing 27/27 for descentmk1, fr645m and fenix5plus on
15 Nov 2026. That is **not** a run of this runner and does not establish
fenix5 or automated startup/reuse behaviour. Do not build images or start
the GUI on a headless agent. On the graphical workstation, after reviewing
the image and access implications:

```sh
cat > /tmp/connectiq-sim.Containerfile <<'EOF'
FROM ubuntu:22.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    libwebkit2gtk-4.0-37 libsecret-1-0 libexpat1 libxext6 libsm6 libusb-1.0-0 \
    fontconfig fonts-dejavu-core && rm -rf /var/lib/apt/lists/*
EOF
podman build -t localhost/connectiq-sim-jammy -f /tmp/connectiq-sim.Containerfile /tmp
cat > /tmp/connectiq-sim-wrapper <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SDK_BIN="$(connect-iq-sdk-manager sdk current-path --bin)"
exec podman run --rm --network=host --ipc=host --userns=keep-id \
  -e DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix:ro \
  -v "$HOME:$HOME" -w "$PWD" localhost/connectiq-sim-jammy "$SDK_BIN/simulator"
EOF
chmod 700 /tmp/connectiq-sim-wrapper
xhost +SI:localuser:"$USER"
# Run from the checkout; use an absolute path if running elsewhere:
bash tools/monkeyc-tests/run.sh --sdk "$SDK" \
  --simulator-cmd /tmp/connectiq-sim-wrapper --output "$HOME/ciq-test-results"
xhost -SI:localuser:"$USER"
```

Revoke the X grant even on error; preferably put the last command in a shell
`trap` before running the script. `--simulator-cmd` takes **one executable
path**, quoted as one argument if it contains spaces. It never evaluates a
shell command string. The wrapper owns its container lifetime; if a simulator
is already listening, the runner does not invoke it. The container mounts the
whole `$HOME`, shares the host network and IPC, and has X access: **this is
not strong isolation**. `--ipc=host` avoids an X MIT-SHM `BadValue` crash;
without the xhost grant X reports `Authorization required`. Do not use this
route on an untrusted image. Optional Xvfb may provide a display where
already installed, but it does not supply missing native WebKit libraries.

## Separate Descent Mk1 physical smoke check (human only)

Build a **normal**, non-`-t` PRG with the same isolated staged source and a
fresh disposable key; retain only the PRG. Run from the checkout:

```sh
SDK_BIN="$(connect-iq-sdk-manager sdk current-path --bin)"
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
umask 077
mkdir -p "$WORK/stage" "$HOME/ciq-sideload"
python3 tools/monkeyc-tests/stage.py "$PWD" "$WORK/stage"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>"$WORK/openssl.log" |
  openssl pkcs8 -topk8 -nocrypt -outform DER -out "$WORK/key.der"
(cd "$WORK/stage" && "$SDK_BIN/monkeyc" -d descentmk1 -f monkey.jungle \
  -o "$WORK/descentmk1.prg" -y "$WORK/key.der" -w)
cp "$WORK/descentmk1.prg" "$HOME/ciq-sideload/descentmk1.prg"
```

Preserve the existing installation/settings before manually sideloading with
your established Garmin procedure; there are **no automated device writes**.
Check installation, startup and safe behaviour without a Metro key. Live
departures are not required. Simulator tests are not a physical-device
result; do not assume unit tests run on the watch. Report the SDK version,
all four device summaries, whether tests work without Metro credentials, and
the distinct physical smoke-check outcome. Human simulator runs of this script,
startup/reuse/timeout checks and the physical sideload remain pending.
