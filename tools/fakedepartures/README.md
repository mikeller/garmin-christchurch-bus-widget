# Offline departure fixtures

This is a simulator-only, standard-library Python 3 server. It never contacts
Metro, needs no Metro API key and does not read app secrets. Its request log
prints only the HTTP method, URL **path** and status, never headers or query
parameters. It ignores the subscription-key header the widget sends. Do not
expose this test server to the internet. Real watches require HTTPS.

## Run with the Connect IQ simulator

```sh
python3 tools/fakedepartures/serve.py --list-scenarios
python3 tools/fakedepartures/serve.py
# In another terminal, inspect a fixture:
curl 'http://127.0.0.1:8765/rti/siri/v1/sm?stopcode=90000'
```

The server listens on `0.0.0.0:8765` by default so a simulator in a Podman
container using `--network=host` can reach
`http://127.0.0.1:8765/`. Alternatively use
`http://host.containers.internal:8765/` if your container resolves that name.
You can select a different bind address and port with `--host` and `--port`.

In the simulator's properties editor, set **Custom Server URL** (`customUrl`)
to **`http://127.0.0.1:8765/`**, with the final slash. The app appends the
literal `rti/siri/v1/sm` to this base, then passes `stopcode` as a separate
request parameter. Thus the actual request is
`GET /rti/siri/v1/sm?stopcode=90000`, not `/sm?stopcode=90000`.
The server accepts `/sm` too for manual testing. Do not put `?scenario=...`
in `customUrl`: concatenation would put `rti/siri/v1/sm` inside the query
instead of the URL path. To force a scenario for *all* stop codes, restart the
server with `--scenario busy`; query overrides work for manual curl requests
(`?stopcode=90000&scenario=busy`).

On Linux, if the simulator settings do not persist, the known workaround is
to pass a settings file to `monkeydo`:

```sh
monkeydo <prg> <device> -a "<build>-settings.json:GARMIN/Settings/<PRG-BASENAME-UPPERCASE>-settings.json"
```

Replace the placeholders with your `.prg` path, simulator device, local settings
JSON path and uppercased `.prg` basename. Configure `customUrl` and the desired
stop codes in that simulator settings file via the properties editor. The exact
simulator menu for disabling **use device HTTPS requirements** varies by SDK;
from memory this option may need to be off to permit plain HTTP.

| Stop code | Scenario |
| --- | --- |
| 90100-90104 | Multi-stop coverage: shared line and destination, opposite direction, short turn and mixed new service |
| 90000-90009 (and other unlisted codes) | Normal, five visits, short and long destinations, `Rāpaki` and parentheses |
| 90010 | Busy, 32 visits, approximately 43 KB |
| 90011 | Medium, 12 visits, approximately 16 KB |
| 90020 | Empty, 324-byte JSON body with `OtherError.ErrorText = "No trips on stop."` |
| 90031, 90033 | HTTP 401, HTTP 403 |
| 90050, 90053 | HTTP 500, HTTP 503 |
| 90060, 90061 | HTTP 200 non-JSON, truncated JSON |
| 90070 | Slow normal response, `--delay` seconds (default 5) |
| 90080 | Malformed visits missing destination, route and departure time |

Fixture times are regenerated on every request, with departures beginning
three minutes from now and four-minute intervals thereafter. `ValidUntil` is
two minutes from now. All timestamps are UTC ISO 8601 with a `Z` suffix.
The larger responses contain ancillary synthetic SIRI journey data, not a
byte-for-byte capture of the real API. The empty body is padded with legal JSON
whitespace to 324 bytes; the exact real response's ancillary fields are not
claimed to be reproduced. A cached response may hide a newly selected
scenario until `ValidUntil` expires or the app's cache is cleared.

## Optional nearby-stop tiles

With `--tiles-dir /path/to/generated/tiles`, the same server serves files
from that directory at `/t/<ty>/<tx>.json` and `/meta.json`. Set
`customTilesUrl` to `http://127.0.0.1:8765` for a nearby-feature build:
that reader appends `/t/<ty>/<tx>.json` to its base. Missing tiles return 404.
For manual tests, add `?scenario=empty`, `?scenario=http500`,
`?scenario=malformed` or `?scenario=slow` to a tile URL (slow uses `--delay`).
The tile `empty` fixture has `"s":[]`; the `malformed` fixture is truncated
JSON. For an app-driven failure scenario, use `--scenario` instead of adding
a query to the base URL. Without `--tiles-dir`, tile endpoints are disabled.

## Test

```sh
python3 -m unittest discover -s tools/fakedepartures
```
