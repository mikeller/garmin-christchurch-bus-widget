# Nearby service validation and rollout gate

The service-key reader and selector must be shipped together, before enabling
service metadata in the tile producer. A simulator pass is not hardware
acceptance. Keep publication pending until the human checks below are supplied.

## Reproduce locally

Use a scratch checkout made with `git archive HEAD` in a temporary directory.
Copy `resources/strings/secrets.xml.template` to `secrets.xml` **only in that
scratch checkout**, and generate a disposable 4096-bit PKCS#8 DER developer key
there. Do not read or copy the maintainer's credentials or signing key. Build
with `monkeyc -f monkey.jungle -d fr645m -y disposable.der -o fr645m.prg -t`,
then run `monkeydo fr645m.prg fr645m -t`. Delete the scratch key afterwards.
Run the equivalent tests on `descentmk1`, `fr945`, `fenix5`, `instinct2` and
`fr55`. Inspect the final `PASSED (passed=..., failed=0, errors=0)` line;
the host runner can exit with status 1 even on a pass. Compile every manifest
device in both normal and test modes, then export a release package from a
scratch copy with `manifest_beta.xml` copied over `manifest.xml`.

`NearbyIntegrationHeapTests.mc` is test/debug-only. Its 56-stop ASCII fixture
is 3826 bytes in compact JSON, the boundary fixture is 4096 bytes, and the
single-stop 1296-key fixture tests the bounded decoder. These objects are
constructed *after* the SDK's JSON parsing boundary: they do **not** measure
network JSON parsing, BLE transfer, a real ~16 KiB or ~43 KiB SIRI response,
or peak allocation between sampling points. The logged `HEAP` free/used/total
values are snapshots of `System.getSystemStats()`, with elapsed milliseconds
from `System.getTimer()`. Report the minimum observed free value as a sampled
minimum, never as the true peak. The simulator may grant a different heap
from the device's official widget memory limit; never substitute one for the
other. Storage assertions prove the simulator accepted writes and eviction,
not that the physical device will. If a full-size response, on-device heap,
both writes and reload/eviction, or operating margin cannot be measured,
the deployment gate remains **FAIL / pending evidence**.

The producer's `--service-metadata` run on the local 18 Nov 2026 GTFS
snapshot (generation date `2026-11-18`) produced 1,435 tiles, with a maximum
of 3,812 UTF-8 bytes and 56 stops in one tile. This is a single offline
snapshot, not proof that future feeds fit. Keep real-feed outputs outside
the repository. The synthetic 3,826-byte fixture is a slightly larger
equivalent shape; it is not a copy of Metro rows.

### Host simulator evidence, 19 Nov 2026

Connect IQ SDK `9.3.0-2026-10-20-95888f262`; official fr645m and
descentmk1 `compiler.json` deviceVersion
`3d0fb192a2cf01699aefd0f384af3f527e5885bd`. The manifest declares a
widget with Communications and Positioning; 37 targets, 13 excluding nearby.
Official widget limits: fr645m 524,288 bytes, descentmk1 1,048,576 bytes.
The simulator instead reported `totalMemory=8,383,928` bytes on fr645m
in the test, so **do not calculate an on-device safety margin from these
simulator values**. The minimum *sampled* free value was 8,176,192 bytes
after constructing a 1,296-key encoded string, with 207,736 bytes used.
Before constructing the fixture, free/used were 8,213,200/170,728 bytes.
After validating the 56-stop fixture they were 8,207,456/176,472 bytes
(6 ms elapsed); after selection with 16 favourites and target 5 they were
8,206,936/176,992 bytes (183 ms elapsed); after the first write
8,206,920/177,008 bytes (186 ms); after the second write
8,201,656/182,272 bytes (189 ms); after reload
8,195,552/188,376 bytes (192 ms); after eviction and reload
8,190,288/193,640 bytes (200 ms); after constructing and validating the
4096-byte boundary shape 8,184,912/199,016 bytes (204 ms); after the
bounded-key check 8,176,192/207,736 bytes (231 ms). All elapsed values
are cumulative since test start, not isolated stage timings. Both writes,
reload and eviction were asserted successful in this simulator test only.
No true peak or JSON pre-parse heap was recorded.

The final fr645m, descentmk1 and fr945 host `monkeydo -t` runs passed
80/80 each, including the oversized-core rejection assertion.
fenix5, instinct2 and fr55 passed 12/12 each. All 37 normal and 37 test
builds passed; the beta release export reported 80/80 devices. Python
`unittest discover -s tools/stoptiles` passed 128 tests. The simulator
runner does not set location or phone settings, and the fake ~16 KiB/~43 KiB
departure payloads were **NOT RUN**. Physical Mk1 and fr645m tests,
real BLE timing, on-device cache capacity and safety margin: **NOT RUN**.
The deployment gate therefore **fails** pending those measurements and
the human checklist.

`customTilesUrl` can target an offline tile server and `customUrl` can target
the fake SIRI server in `tools/fakedepartures` in a local read-only checkout.
Set both in the simulator settings editor, position the simulated device
beside the served tiles, and repeat with stale/offline data. These settings
and GPS quality cannot be set by the host-only test runner. Never infer
network or page behaviour from pure selection tests.

## Human-only Mk1 checklist: PENDING

- Walk a real corridor: shared service and opposite directions, loops, and
  partial overlap. Confirm **all** departures are displayed at a retained
  overlap stop, including the routes not involved in deduplication.
- Check nearer and farther favourites, no favourite, counts 1, 3, 5 and
  fewer, and a service key needed beyond the nearest 15 stops.
- Walk more than 100 m, check position/refresh and cached/offline fallback,
  page navigation and wrap, and capture memory/error logs on a Descent Mk1.
- Confirm title/glance reads cached data only on an officially compatible
  glance device; Mk1 has no widget glance.

## Human-only beta and real-key steps

Keep `manifest_beta.xml` as the separate beta identity. Increment the beta
store version on **each** beta upload. Use the existing 4096-bit developer
key for the Mk1 beta export; disposable build keys are only for local tests.
Enter real Metro credentials only through the maintainer's normal private
workflow, not in source or fixtures. Sideloaded defaults are not the phone's
beta-store settings: configure and verify `customTilesUrl`, `customUrl`,
nearby enablement and count on the actual phone separately. Distribute the
reader first, then validate the generator and the human checklist; publication
requires separate authorisation. Do not publish based on simulator evidence.
