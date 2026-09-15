# History

An earlier iteration of this app scraped the source sites directly, in a Dart port of the
backend's engine (`core/core.dart`, `core/providers/`, `core/extractors/`, `core/http/`,
`core/utils/`). That's gone — content comes from the API now, so the port had no callers and
would only have rotted. `core/models/` survived it: those classes mirror the backend's
`core/models/*.ts` field-for-field, which is exactly what the API responses deserialize into.

Removed with it: `dio_cookie_manager`, `cookie_jar` and `html` (session cookies and HTML parsing
were scraping-only concerns) and `jwt_decoder` (never used — the app doesn't inspect token
claims, it just replays a 401). `freezed`, `json_serializable` and `riverpod_generator` went too;
nothing in the tree was annotated for them, so `build_runner` was walking the whole project on
every run to generate nothing. Drift is the only code generator left.
