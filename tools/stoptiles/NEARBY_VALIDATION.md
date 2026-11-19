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

## Real-device Mk1 finding, 19 Nov 2026: watchdog crash, fixed pending re-test

A beta export of this branch was installed on a real Descent Mk1
(Part-Number 006-B2859-00, Firmware 16.10, ConnectIQ 6.0.4) and crashed three
times on 18 Nov 2026 with `Watchdog Tripped Error - Code Executed Too Long`,
`Details: 'Failed invoking <symbol>'`, read from the device's
`GARMIN/APPS/LOGS/CIQ_LOG.YML`. The stack (`pc: 0x10006119`, `pc: 0x100048c1`)
was not symbolicated; no debug.xml/ERA download was available for this
investigation. This is a CPU-time watchdog, not an out-of-memory error: it
confirms real hardware is slower than assumed for at least one nearby code
path, not the memory-margin risk this document previously called out.

Root cause (by code inspection, not by reproducing the crash): a loaded tile
can validly hold up to `NearbyServiceContext.MAX_STOPS` (292) rows, and
`NearbyCoverageSelection.select()`/`whollyCovered()` re-scanned every row (and
re-ran a full favourites membership and distance scan) for every rejected
candidate, giving roughly O(rows² × favourites) work with no bound relative
to a real stop cluster. This only runs synchronously inside the tile
download's web request callback (`ChristchurchBusViewManager`'s `onTile`),
exactly where the Connect IQ watchdog measures a single callback's run time.
It was validated only against small synthetic fixtures (at most 40 rows, see
above), never against a real, busier interchange-style cluster, and never
timed on real hardware; the host simulator does not model real-device CPU
speed any more than it models the real widget memory limit.

Fix applied: `NearbyCoverageSelection` now builds a favourites lookup once
instead of a linear scan per row per candidate, and precomputes the
in-tile favourites sorted by distance once, folding each one into the
covering-provider set at most once for the whole call (the candidate
distance only ever grows during the scan, so this is a straightforward
incremental rewrite, not a change to the selection rules). This removes the
`× favourites` (up to 16) factor from both hot loops without changing which
stops are chosen or in what order; every assertion in
`NearbyCoverageSelectionTests.mc` was hand-traced against the rewritten code
and matches. The existing SDK here (7.0.0 Beta1) cannot type-check or run
this codebase (it predates several Toybox APIs this branch already uses, and
its host simulator will not start on this machine: `libwebkit2gtk-4.0` is no
longer packaged), so this fix has **not** been executed through
`monkeydo -t`, run against a real-sized tile, or timed on any device or
simulator. Re-run the full validation in "Reproduce locally" above (ideally
with real or near-real stop-cluster density, not just the existing small
fixtures) and repeat the real Mk1 walk before trusting this fix on hardware.

## Re-verification, 19 Nov 2026: working SDK 9.3.0 toolchain

A working local toolchain became available (Connect IQ SDK 9.3.0, the
`descentmk1` device profile, and a simulator reachable over `monkeydo -t`
through a short-lived Docker container supplying the `libwebkit2gtk-4.0` ABI
the simulator binary needs; see
`/tmp/opencode/ciq-sdk-work/run-ciq-tests.sh` on the machine this was done
on, not part of this repo). A `monkeydo -t` run against `descentmk1` on
commit `b311cd2` (the coverage-selection performance fix above) found 79
passed, 1 failed: `testNearbySelectionKeepsLastFavourite`, with all
`NearbyCoverageSelectionTests.mc` and `NearbyIntegrationHeapTests.mc` tests
passing.

### Favourite-restore bug: Storage round-trips a Number as Long

Root cause, confirmed by reproducing the failure and adding temporary debug
output (not by inspection alone): `Time.Moment.value()`'s `resetTime` is
written to `Storage` as what the compiler treats as `Lang.Number`, but
`Storage.getValue()` returns it back typed as `Lang.Long`, confirmed via a
real `Storage.setValue()`/`getValue()` round trip in the SDK 9.3.0 simulator
on `descentmk1` (not yet confirmed on physical hardware; Monkey C's docs for
`Time.Moment.value()` state `Lang.Number`). `StoredBusData.validLastStop()`
required `entry["resetTime"] instanceof Number`, so a perfectly valid,
unexpired restart record was rejected as malformed and discarded. This
affects every reader of the shared `Constants.LAST_STOP_INDEX_NAME` record,
including `ChristchurchBusDataCache.getLastStop()` — the pre-existing,
non-nearby "remember last stop on startup" feature that predates this
branch — not only the new nearby favourite-memory path. This is very likely
the actual mechanism behind the previously reported "remembering the last
favourite page shown still does not seem to work" symptom; the three
previously listed hypotheses (`setLastStop`'s early-return on
`favourites[0]`, `stopResetTimeMin` default-0 semantics, a nearby-only-exit
problem) were investigated and are not the cause — each behaves as designed.

Fix: `StoredBusData.isStoredInteger()`/`toStoredNumber()` now accept and
normalise both `Number` and `Long` for a persisted integer, used by
`StoredBusData.validLastStop()`, `NearbyFavouriteMemory.restore()` and
`restoreReason()`, and `ChristchurchBusDataCache.getLastStop()`. `stopId`
and `stopIndex` were not observed to round-trip as `Long` in this testing
(only `resetTime`, the one field derived from `Time.Moment.value()`) and
were left as `Number`-only checks; if a future report suggests otherwise,
re-check them the same way. `NearbyStoredFix.mc`'s structurally similar
`"at"`/`"savedAt"` fields (GPS fix caching, a different storage key) were
**not** touched: no test currently fails there, and it is out of this
fix's scope, but it uses the same `Time.Moment`-derived-timestamp-via-Storage
pattern and is worth checking if a similar symptom is ever reported for GPS
fix caching.

All 80 existing tests plus one new timing test (below) passed under SDK
9.3.0 on `descentmk1` after this fix, with no regressions to
`NearbyCoverageSelectionTests.mc` or `NearbyIntegrationHeapTests.mc`.

### Coverage-selection performance fix: re-verified, with timing evidence

Under the working SDK 9.3.0 toolchain, `NearbyCoverageSelectionTests.mc` and
`NearbyIntegrationHeapTests.mc` both pass on `descentmk1` (previously only
confirmed by hand-tracing against a mismatched SDK). A new test,
`testNearbyCoverageWorstCaseTiming` in `NearbyCoverageTimingTests.mc`
(`:debug` only, not shipped), constructs a 160-row tile (the same scale as
the existing "bounded tile full scan" coverage test; 292 rows is not
reachable while staying `NearbyServiceContext.usable()`, since `MAX_BYTES`
caps the practical row count well below the 292 array-size cap for any
non-trivial name length) with 16 favourites and a key pattern designed so
almost every candidate is rejected as covered, maximising scan iterations.
Measured with `System.getTimer()` in the Dockerised host simulator (not real
hardware, and not a true peak): the pre-fix algorithm (commit `794765a`)
took 2,329 ms for this fixture; the fix (commit `b311cd2`) took 688 ms, a
~3.4x improvement on this synthetic worst case. This is host-CPU evidence of
a real, measured improvement with the expected direction and rough
magnitude, not a substitute for timing on physical Mk1 hardware, and not a
guarantee the remaining cost fits inside the watchdog's budget on a slower
real CPU for an even larger real-world cluster.

## Human-only Mk1 checklist: PENDING

- Walk a real corridor: shared service and opposite directions, loops, and
  partial overlap. Confirm **all** departures are displayed at a retained
  overlap stop, including the routes not involved in deduplication.
- Check nearer and farther favourites, no favourite, counts 1, 3, 5 and
  fewer, and a service key needed beyond the nearest 15 stops.
- Walk more than 100 m, check position/refresh and cached/offline fallback,
  page navigation and wrap, and capture memory/error logs on a Descent Mk1.
  Error logs are at `GARMIN/APPS/LOGS/CIQ_LOG.YML` (and `.BAK` for the
  previous crash) over USB; they are overwritten by the next crash, so copy
  them off before launching anything else. A busier real stop cluster
  (shared/opposite-direction services, an interchange) is the scenario most
  likely to retrigger a watchdog timeout; test near one, not only in a quiet
  area.
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
