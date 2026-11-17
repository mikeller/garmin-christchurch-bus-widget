# Offline service-key decision

**Updated decision: conditional go for the global-numbered wire design;
no-go for deploying generator, reader or selection changes pending the
human's consistency and device-validation decision.** The global measurement
below supersedes the earlier tile-local dictionary size conclusion. The
original decision was no-go for generator, tile-reader and selection changes. The
preferred key is `(GTFS route_id, GTFS direction_id)`, scoped to a GTFS
snapshot, not a SIRI display string. The preferred wire shape is additive
tile-root metadata with `v:1` and exactly four fields per `s` row. On the
sample below, even the compact dictionary encoding exceeds the existing
4096-byte limit in four tiles. Do not silently raise the cap, change tile
membership, or add a metadata request. Re-plan the size/coverage/request
trade-off and validate on a second feed before downstream implementation.

## Reproduce

Run `python3 tools/stoptiles/analyse_service_keys.py /path/to/gtfs.zip >
/tmp/service-keys.json` from the repository root, then
`python3 -m unittest discover tools/stoptiles`. Stdlib only; the command
prints aggregate JSON and does not write feed data into the repository. It
uses the production `parse_stops`, `build_tiles`, `encode_tile` and `nearest`
functions, with the production membership and raw UTF-8 names. Inputs were
the local Metro GTFS ZIP downloaded **18 Nov 2026 01:54 NZDT**,
6,168,666 bytes, SHA-256
`ca733925eb5ce6743e3375679e6599249066ac049e751cd706e124750a4cac9c`.
This is a snapshot, not a claim about future updates. The ZIP and rows are
not included here. All committed test inputs are synthetic.

Feed info and calendar run **8 Nov 2026 to 4 Apr 2027**; calendar exceptions
span **12 Nov 2026 to 29 Mar 2027**. These bounds describe *scheduled*
service validity, not the date a route runs at a particular stop or real-time
departures. Rebuild on each changed feed and reject an expired service horizon.
Existing `meta.json` hashes only filtered stop names/coordinates/codes;
service changes can occur with the same `h` and `gv`. A 304 proves only that
the *remote ZIP* was unchanged, not that a generator or parser revision is
unchanged. A service-aware release should define `sh` as SHA-256 of compact
UTF-8 JSON (`ensure_ascii=False`, separators `(",",":")`) of
`[existing stops h, feed start date, feed end date, [[publicCode,
reliability, [[route_id,direction_id],...]],...]]`, with both inner and outer
lists sorted (keys lexicographic by ID then direction; codes numeric). No
tile-local index enters this digest. The deployed meta must expose `sh`,
and each service tile must bind to it and `g`; a reader must invalidate its
service cache on changed `sh`, not merely changed `g`. A new generator version
and deployment decision keyed on this digest are needed before rollout.

## Join and semantics

Join `stops.stop_id -> stop_times.stop_id -> stop_times.trip_id ->
trips.route_id -> routes.route_id`; expose `stops.stop_code` only after that
join. Of 2,083 input stops, all 2,083 pass current generator filtering and
have complete key sets (100% complete, 0 partial, 0 unknown) in this snapshot.
There are 499,323 stop-time rows; every trip service ID has a calendar or
exception entry. There are 60 distinct `(route_id,direction_id)`
keys, at most 11 keys per stop; **zero** orphan stop/trip/route rows, duplicate
stop/trip/route IDs, invalid/missing directions or unresolved public codes.
There are 29 short-name collisions across route IDs: `route_short_name` alone
is not an identity. The join audits ambiguous duplicate IDs and stop-code
mapping separately; an unresolved or empty stop is unknown, a stop with
valid keys and broken joined rows is partial. Neither is safe to hide.

There are 860 additional visits to the same stop within one trip (loops).
They do not create new keys. Nineteen route/direction keys have multiple
trip-level headsign pairs; all 19 vary at trip level and **none** vary at
stop-level headsign in this snapshot. This is evidence of variants, not
evidence that express or short-turn destinations should be separate coverage
identities. No destination discriminator is proposed without a demonstrated
misleading suppression example. Pickup restrictions: zero restricted rows
and zero stops with restricted-only keys in this snapshot. The audit excludes
restricted pickup from boardable keys and counts restricted-only keys;
additional feeds must validate non-default pickup semantics and calendars.
SIRI `PublishedLineName`/`DestinationName` correspondence is **UNVERIFIED**:
no independently supplied sanitised live sample was available. Runtime
equality to SIRI is neither used nor required.

Static keys describe the union of scheduled, boardable trips throughout the
feed horizon, not current departure availability. The audit includes all
`trips.txt` service IDs with stop-time visits; it does not prove each service
ID has an active calendar day. A production build must intersect service IDs
with calendar and calendar-date validity in its declared horizon, and mark
unresolved references unknown rather than silently treating them as absent.
Unknown/partial states
remain visible, even if known keys overlap. For *complete* stops only, walk
nearest first (exact watch squared-distance approximation), ties by public
stop code; retain if any key is not already covered, otherwise discard.
Retained stops still show **all** their actual departures. Favourites always
remain pages; they contribute coverage only if present in the loaded
candidate tile and strictly closer than the stop considered (on distance
ties they do not pre-cover it). Never fetch distant favourites for coverage.
Keep configured count 1..5, default 3; fewer than target is fine.

## Wire proposal and compatibility boundary

Proposed *conditional* v1 additive root (synthetic vector; not production):

```json
{"v":1,"g":"2026-11-18","s":[[1001,-4350000,17260000,"Synthetic"],[1002,-4350001,17260001,"Synthetic"]],"m":1,"sh":"0000000000000000000000000000000000000000000000000000000000000000","k":[["route-A",0],["route-B",1]],"i":[[1001,[0,1]],[1002,[1]]],"p":[1002]}
```

`m=1` is the independent service-metadata schema version; `sh` is a
64-character lower-case hex service digest equal to deployed `meta.json`'s
service digest, with generation `g` matching the corresponding tile. All-zero
`sh` above is a synthetic placeholder only, not a digest for a real feed.
`k` is sorted
lexicographically by exact UTF-8 GTFS `route_id` then numeric direction 0/1.
Indices are **zero-based and scoped to this tile only**, bounded
`0 <= index < len(k)`, without duplicates; `k` is non-empty when known rows
exist. `i` is sorted by public stop code; each code occurs once, must be in
`s`, and has a non-empty sorted unique index list. `p` is a sorted unique
subset of codes in `i`, marking partial knowledge. An `s` code absent from
`i` is **unknown**, not empty/covered. Code in `i` and not in `p` is complete.
No cross-tile comparison of integers: compare the resolved `(route_id,
direction_id)` strings instead. Bound row codes to 1000..99999, direction to
0/1, arrays and decoded masks to tile-local lengths, and entire wire body
to 4096 UTF-8 bytes. Reject duplicate dictionary keys, malformed indices,
unknown schema versions, generation mismatch and non-string route IDs. On any
malformed or absent metadata, keep the legacy tile usable but treat *every*
stop as unknown; never suppress a stop. The synthetic
`service_key_vectors.json` and `decode_metadata` provide a reference for
future producer/reader tests, not a production parser. A valid `m=1` with zero `i` and zero
`k` encodes all-unknown. Future producer and reader should share synthetic
vectors for duplicate/out-of-range indexes, partial/unknown and cross-tile
dictionary collisions, plus old cache fixtures.

The inspected `ChristchurchBusTileReader.validTile` on
`feat/nearby-tiles-#692` ignores extra root keys but requires `v==1` and
**exactly four** fields in each `s` row. Its cache stores the entire root
under `nearby:<ty>,<tx>`, checks `g`, uses a three-day TTL (offline stale
allowed), and keeps at most two tiles. The callback currently passes only
`tile["s"]`, losing root metadata. A later reader must explicitly validate
and propagate metadata, keep old `v=1` cached entries valid as all-unknown,
never mistake a stale metadata-less tile for complete, and account for parsed
object-store overhead. Changing `v` or adding a fifth stop field would break
the legacy reader. If additive metadata cannot fit, a *separate versioned
URL* such as `svc/v1/t/<ty>/<tx>.json` may retain the legacy endpoint, but
requires an extra request, cache/atomic-generation checks and explicit
re-planning. Do not overwrite the legacy endpoint incompatibly.

## Whole-feed tile sizes

1,435 production-selected tiles; compact UTF-8 JSON with raw stop names and
generation `2026-11-18`. `naive` adds `[code,[[route_id,direction],...]]`;
`index` adds `m,sh,k,i,p` as above; `bitset` uses the same `k,p` and
`b:[[code,base64(little-endian-bitset)],...]` instead of `i`. All include
legacy `v,g,s`; all metadata candidates include `m,sh` with a fixed-width
64-character digest placeholder. p95 is nearest-rank 95th percentile. Overflow is **strictly
greater** than 4096 bytes.

| Encoding | Max bytes | p95 bytes | Tiles >4096 | Worst tile (ty/tx, stops) |
| --- | ---: | ---: | ---: | --- |
| Legacy | 3238 | 1993 | 0 | -4354/17264, 56 |
| Naive | 6722 | 3414 | 28 | -4354/17263, 50 |
| Dictionary/index | 4954 | 2708 | 4 | -4354/17264, 56 |
| Dictionary/bitset | 5039 | 2773 | 4 | -4354/17264, 56 |

For index: next worst are -4354/17263 (4668 bytes, 50 stops)
and -4353/17264 (4311 bytes, 53 stops). For bitset: 4616 and 4333
bytes respectively. These are *wire* sizes, not parsed sizes. **Estimate**
for parsed watch objects: each added nested array, dictionary entry and
string has allocator/header/reference overhead (order of tens of bytes
each); an extra 50 stops with index arrays may add several kilobytes to the
already cached tile. No device heap or object-store measurement was made.
Do not infer the documented 32 KB per-value limit guarantees a write.

## Bounded coverage probe

For each tile, compare five points (E5 centre and four inclusive corners)
against all feed stops within +/-2698 latitude E5 and +/-3719 longitude E5
of the point, nearest-first with limit five. The tile side uses **the
generator's actual chosen membership**, and the 15 side scans only the nearest
15 of that membership. These are 7,175 deterministic points, not measured
user positions. At 2,810 points the tile has fewer than 15 candidates;
961 points produce different retained codes with first-15 versus the *full
tile*. At 3,444 points full-tile selection differs from point-centred,
full-feed cap selection (including cases where tile membership extends beyond
the point-centred cap). Thus a 15-entry truncation is **not sufficient** for
exact distinct-service selection; existing `MIN_STOPS=15` is a minimum tile
membership, not a selection cap, and many mismatch probes result from the
different rectangular search windows. Preserve bounded current tile coverage
and allow fewer pages; do not silently widen tile grid, cap or request count.

**Downstream gates:** generator NO-GO until a bounded encoding passes all
tiles and service digest/validity decisions are specified; reader NO-GO
until that wire version, cache/fallback and memory budget are validated;
selection NO-GO until the agreed candidate bound and tile-versus-cap
behaviour are decided. The key semantics themselves are ready for synthetic
producer/reader contract tests. SIRI equivalence, future feed variability,
on-device memory and real-world boundary coverage remain UNVERIFIED.

## Updated measurement: global service-key numbering

**This section supersedes the tile-local dictionary size gate and the
preceding downstream gates, but not the coverage caveat.** Re-run the command
above (without `--skip-probes`) to obtain every tile's sizes in `per_tile`,
the worst ten in `global_sizes`, round-trip counts and selection checks.
All candidates keep legacy `v:1`, `g`, raw four-field `s` rows, plus `m:2`,
`sh` (64 hex characters), `K` (global numbering size), and `p` (partial
stop-code list, empty here). The analysis assigns numbers 0..59 to the
lexicographically sorted `(route_id,direction_id)` pairs. **No route dictionary
is shipped in tiles or needed on the watch.** All measurements include the
same 64-character placeholder digest. The 60-entry global table encoded as
compact UTF-8 JSON is **1,089 bytes**; publishing it as a `meta.json` member
for audit would add at least 1,089 bytes plus its member name, punctuation
and any escaping required by the chosen JSON serialiser. It is not a watch
dependency.

`pairs` is `i:[[code,[index,...]],...]`; `parallel` is an `i` array aligned
with `s`, containing an index list or `null`; `base64` and `hex` encode a
fixed `ceil(K/8)` byte, little-endian unsigned mask as a string, paired with
the stop code. No mask is a JSON integer (Monkey C Number is 32-bit; Long is
64-bit). `sets` has `q` as sorted distinct index lists in this tile and
aligned `i` with a tile-local set index or `null`; never compare set indexes
across tiles. `base36` has aligned `i` containing two lower-case base-36
digits per *global* index, concatenated in increasing order, or `null`.
This last encoding saves array and stop-code repetition; its fixed width
supports K up to 1,296. Distinct sets per tile: median 4, p95 14, max 35.

| Encoding | Max B | p95 B | Median B | Tiles >4096 | Worst-tile headroom |
| --- | ---: | ---: | ---: | ---: | ---: |
| Global pairs | 4358 | 2577 | 1229 | 1 | -262 B |
| Global parallel | 3910 | 2297 | 1106 | 0 | 186 B |
| Global base64 mask | 4624 | 2911 | 1353 | 5 | -528 B |
| Global hex mask | 4848 | 3055 | 1417 | 10 | -752 B |
| Global set table | 3942 | 2247 | 1077 | 0 | 154 B |
| **Global fixed-width base36** | **3812** | **2304** | **1095** | **0** | **284 B** |

Worst ten in descending byte order, as `ty/tx:bytes`; all numbers include
unchanged names. The output JSON also provides each tile's stop count.

| Encoding | Worst ten tiles |
| --- | --- |
| Pairs | -4354/17264:4358; -4354/17263:4053; -4353/17264:3939; -4352/17267:3936; -4355/17264:3692; -4352/17264:3683; -4351/17265:3667; -4352/17265:3626; -4355/17262:3540; -4353/17257:3510 |
| Parallel | -4354/17264:3910; -4354/17263:3653; -4353/17264:3515; -4352/17267:3496; -4355/17264:3292; -4351/17265:3259; -4352/17264:3259; -4352/17265:3226; -4355/17262:3148; -4353/17257:3126 |
| Base64 | -4354/17264:4624; -4352/17267:4405; -4353/17264:4334; -4352/17264:4198; -4354/17263:4158; -4351/17265:4075; -4355/17264:4060; -4352/17265:4015; -4355/17262:3970; -4356/17261:3945 |
| Hex | -4354/17264:4848; -4352/17267:4625; -4353/17264:4546; -4352/17264:4410; -4354/17263:4358; -4351/17265:4279; -4355/17264:4260; -4352/17265:4215; -4355/17262:4166; -4356/17261:4141 |
| Sets | -4354/17264:3942; -4354/17263:3653; -4352/17267:3501; -4353/17264:3494; -4355/17264:3266; -4351/17265:3223; -4352/17264:3174; -4352/17265:3152; -4355/17262:3095; -4353/17257:3074 |
| Base36 | -4354/17264:3812; -4354/17263:3522; -4352/17267:3477; -4353/17264:3470; -4352/17264:3264; -4355/17264:3248; -4351/17265:3235; -4352/17265:3199; -4355/17262:3140; -4356/17261:3097 |

**Capacity is snapshot-specific.** On the worst base36 tile (56 stops),
the 284-byte gap admits three extra synthetic copies of its longest-name,
richest-key stop (28 UTF-8 name bytes and 10 keys). The fourth makes
4,132 bytes, **36 over** cap. One additional global key on *every* known
stop in this tile adds 112 bytes (3,924 total); two would add approximately
224 bytes if K stays within the two-digit base36 range, leaving about
60 bytes. Growth is not linear when a feed changes names, candidate counts
or the key length encoding. A new route adds one or two global keys:
K grows, but the fixed two-digit form costs nothing at stops *not* served by
those keys. If K exceeds 1,296, fail the build and re-plan a new metadata
schema; never truncate. Re-run the cap check for every new feed. If a later
tile crosses 4,096, the smallest proposed *additional* measure is to
reconsider the aligned representation or a separately versioned metadata
endpoint for that measured excess, with request-count approval; do not
silently narrow membership or raise the cap.

**Parsed-object ESTIMATE, not a Garmin measurement.** Counting the JSON
tree at the 56-stop worst tile, including legacy stop rows, yields:

| Encoding | Arrays | Dictionaries / entries | Strings | Numbers |
| --- | ---: | ---: | ---: | ---: |
| Pairs | 171 | 1 / 8 | 66 | 381 |
| Parallel | 115 | 1 / 8 | 66 | 325 |
| Base64 or hex | 115 | 1 / 8 | 122 | 227 |
| Sets | 95 | 1 / 9 | 67 | 352 |
| Base36 | 59 | 1 / 8 | 122 | 171 |

Assuming roughly 24-48 bytes per parsed array, 32-64 per dictionary,
8-24 per dictionary entry, 24-48 plus UTF-8 payload per string, and 8-24
per boxed number, base36's tree is on the order of **6-12 KB of object
headers/references plus string bytes**, versus roughly **11-23 KB plus
string bytes** for pairs. These are illustrative assumptions, not Monkey C
heap sizes or validated cache write sizes. Base36 decoding also needs
temporary integer state; avoid allocating a string or array per digit pair
in a watch implementation. Device limits and cache writes require tests.

### Recommended exact contract and consistency rule

Recommend **global sorted numbering with a digest-bound base36 encoding**
(`m:2`). Synthetic vector in `service_key_vectors.json`: `K:60`,
`i:["000z","0z",null]`, `p:[1002]` alongside three four-field `s`
rows means complete keys `{0,35}`, partial `{35}`, and unknown. `K`
is the number of canonical global keys, 1..1296; each non-null `i` entry
must be a non-empty even-length string of lower-case base36 pairs that
decode to *strictly increasing* integers in `0..K-1`. `i` length must
equal `s` length. `p` is a sorted unique list of public stop codes, drawn
only from non-null `i` rows; `null` is unknown, never an empty complete
set. Bound stop codes to 1000..99999, reject duplicate codes and mismatched
generation or unknown `m`. The JSON root must remain <=4096 UTF-8 bytes.
Treat malformed, absent, unsupported, unmatched-digest or stale-expired
metadata as **all unknown**, retaining the legacy `s` rows and all pages.
Reader must check the digest before suppressing any candidate. `K` permits
range validation without downloading the global table.

Define new `sh` as SHA-256 over compact UTF-8 JSON
`[2,g,existing_stops_h,feed_start,feed_end,
[[route_id,direction_id],...],
[[publicCode,reliability,[[route_id,direction_id],...]],...]]`.
Use `ensure_ascii=False`, separators `(",",":")`, sorted canonical
route/direction pairs and numeric public-code order, with the mapping array
ordered by **global index**. Include calendar-effective service changes and
unknown/partial flags; fail closed on invalid service references. Put this
same `sh` in each tile and deployed `meta.json`. The reader need not fetch
meta: compare tile `sh` (and K) directly for *all loaded candidate tiles*
before any de-duplication. The comparison binds the numbering, not just
the service sets. If a 3-day cached tile and a fresh tile differ in `sh`
or K, **every stop in the combined candidate selection becomes unknown**:
retain all candidates nearest-first rather than compare unequal numbers.
An old cache entry with no `m:2` is also all-unknown. A one-tile selection
can use valid metadata for that tile; a stale offline tile must still
honour existing TTL/staleness policy and should fail open when its metadata
cannot be verified. Never compare numbers from different digests.

Alternative append-only numbering: persist the complete immutable registry
in the *published* meta, append new canonical pairs only, retain retired
pairs as tombstones and never reuse indexes. This can keep identities stable
across generations, but `generate_tiles.py --previous-meta` currently only
prints the previous meta for diagnostics. The workflow does not pass it
to the generator; the deployed meta is available only to deployment
decision logic. Implementing an atomic, validated registry read and passing
its predecessor through the workflow would be production changes, with
rollback, missing/corrupt prior meta and tombstone growth to handle.
The measured registry array alone is 1,089 bytes today. Sorted numbering
plus `sh` fail-open is simpler and does not require persistent state.
Sorted positions may shift when one route is added, so a digest mismatch
**must** invalidate cross-generation comparisons. Even append-only
numbering would still require a version/digest check for changed services.

All six global encodings were JSON-serialised, decoded and compared against
source sets across **1,435 tiles and 22,570 tile-stop appearances each**:
zero failed rows, tiles or cross-tile conflicts. For each encoding, decoded
selection matched source-set nearest-first selection on all **7,175**
cell-centre/corner tile probes (zero mismatches). This is equality for
*the same loaded tile*, not a cure for the earlier 961 first-15 or 3,444
tile-versus-point-cap mismatches. Old fixtures, partial, unknown, malformed
and digest mismatch are exercised by synthetic tests.

**Updated downstream gates:** generator **conditional go** for a
separately authorised service-metadata implementation with sorted global
numbering, per-feed cap enforcement and `sh`-aware deploy decision; reader
**conditional go** only after the human approves fail-open mixed-generation
behaviour and on-device cache/heap validation; selection **conditional go**
for bounded current-tile coverage without a 15-entry truncation, retaining
unknowns and all departures. A grid/cap/request change remains **no-go**
without re-planning. The human must decide whether mixed generations may
temporarily disable de-duplication, and which nearby-capable device is the
minimum memory target. On-device memory, SIRI correspondence, future feeds
and that smallest device remain **UNVERIFIED**. No production changes were
made here.
