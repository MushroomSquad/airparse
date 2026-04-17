# get_airflow_vars — Technical Documentation

## Overview

`get_airflow_vars.py` is a self-contained, dependency-managed Python script that extracts the complete environment configuration of an Apache Airflow instance — connections, variables, and secrets — and writes the result to a styled Excel workbook.

It is designed as a single-file tool with inline dependency declarations (`uv` script format), requiring no virtual environment setup.

---

## Architecture

```
main()
├── fetch_api()     ← --mode api
├── fetch_local()   ← --mode local
└── fetch_docker()  ← --mode docker
         │
         ▼
    AirflowData (dataclass)
    ├── connections: list[dict]
    ├── variables:   list[dict]
    └── secrets:     list[dict]
         │
         ▼
    export_excel()  →  output.xlsx
```

All three fetch functions return the same `AirflowData` dataclass, which is then passed to the single `export_excel()` function. The output format is identical regardless of mode.

---

## Module-level components

### `AirflowData`

```python
@dataclass
class AirflowData:
    connections: list[dict]  # conn_id, conn_type, host, port, schema, login, password, extra
    variables:   list[dict]  # key, value, description
    secrets:     list[dict]  # section, key, value, source
```

Single data container shared by all modes. Initialized with empty lists.

---

## API mode — `fetch_api()`

```python
def fetch_api(base_url: str, user: str, password: str, cookie: str | None = None) -> AirflowData
```

### Authentication chain

Tried in order; stops at the first success:

| Step | Method | Notes |
|------|--------|-------|
| 0 | Cookie injection | `--cookie` value parsed into `requests.Session.cookies`; skips steps 1–3 |
| 1 | JWT — Airflow 3.x | `POST /auth/token` → Bearer token |
| 1 | JWT — Airflow 2.x | `POST /api/v1/security/login` → Bearer token |
| 2 | Web-form session | `GET /login` to extract CSRF, then `POST /login`; checks redirect URL |
| 3 | HTTP Basic | `session.auth = (user, password)` — last resort |

### API version detection

```python
for prefix in ("/api/v2", "/api/v1"):
    probe = session.get(f"{base}{prefix}/connections", params={"limit": 1})
    if probe.status_code != 404:
        api_prefix = prefix
        break
```

Probes `/api/v2` first (Airflow 3.x), falls back to `/api/v1` (Airflow 2.x). Exits with an error if neither responds.

### Pagination — `get_all()`

Internal helper inside `fetch_api`. Iterates with `offset`/`limit=100` until `len(items) >= total_entries`. Returns `None` on 401/403/404 (logged, not raised).

### Endpoints called

| Endpoint | Key | Purpose |
|----------|-----|---------|
| `GET /connections?limit=100&offset=N` | `connections` | All connections |
| `GET /variables?limit=100&offset=N` | `variables` | All variables |
| `GET /config` | `sections[].options[]` | Full airflow.cfg (Admin only) |
| `GET /me` or `/currentUser` | — | Whoami (logged, not stored) |

### Connection field mapping

The API returns `connection_id` in both v1 and v2. The script normalises this to `conn_id` in the output, with a fallback:

```python
"conn_id": c.get("connection_id", c.get("conn_id", ""))
```

---

## Local mode — `fetch_local()`

```python
def fetch_local(airflow_home: str | None = None) -> AirflowData
```

Wraps `airflow` CLI via `subprocess`. Uses `AIRFLOW_HOME` env override if `--airflow-home` is set.

| Data | Command |
|------|---------|
| Connections | `airflow connections export /dev/stdout --file-format json` |
| Variables | `airflow variables export /dev/stdout` |
| Config | Direct `configparser` read of `$AIRFLOW_HOME/airflow.cfg` |

The connections export may return either a list (`[{...}]`) or a dict (`{"conn_id": {...}}`); both are handled.

---

## Docker mode — `fetch_docker()`

```python
def fetch_docker(container: str, airflow_home: str = "/opt/airflow") -> AirflowData
```

Uses the Docker SDK (`docker.from_env()`) to `exec_run` commands inside the named container. No SSH, no exposed ports required — communicates directly through the Docker socket.

| Data | Command |
|------|---------|
| Connections | `airflow connections export /dev/stdout --file-format json` |
| Variables | `airflow variables export /dev/stdout` |
| Config | `cat $AIRFLOW_HOME/airflow.cfg` (falls back to `/root/airflow/airflow.cfg`) |
| Env vars | `env` — filtered to lines matching sensitive keywords |

Sensitive env var keywords (case-insensitive match against key name):
```
SECRET  PASSWORD  TOKEN  KEY  AIRFLOW__  FERNET
```

---

## Excel export — `export_excel()`

```python
def export_excel(data: AirflowData, output: str)
```

Produces a four-sheet workbook using `openpyxl`.

### Sheets

| Sheet | Columns |
|-------|---------|
| `Connections` | conn_id, conn_type, host, port, schema, login, password, extra |
| `Variables` | key, value, description |
| `Secrets_Config` | section, key, value, source |
| `Summary` | Sheet, Count |

### Styling

- **Header row**: white bold text on dark blue (`#1F4E79`) background, centered.
- **Alternating rows**: light blue fill (`#D6E4F0`) on even rows.
- **Column widths**: auto-fitted to content, capped at 60 characters.

Implemented in `_write_sheet()` which is shared by all data sheets.

---

## Error handling

The script follows a "log and skip" philosophy for non-fatal errors:

- **403/401 on any endpoint** — logged with response headers and body (first 500 chars), returns `None`/empty, continues.
- **404 on any endpoint** — logged, continues.
- **CLI command failure** — caught per-section, logged, continues.
- **Docker exec failure** — caught per-section, logged, continues.
- **API version not found** — hard exit via `sys.exit()`.
- **`--url` missing in api mode** — `argparse` error.
- **`--container` missing in docker mode** — `argparse` error.

---

## Dependencies

Declared as inline script metadata (PEP 723), managed automatically by `uv`:

```toml
dependencies = [
  "requests",   # HTTP client for API mode
  "openpyxl",   # Excel file generation
  "docker",     # Docker SDK for docker mode
]
```

`docker` is imported lazily inside `fetch_docker()`, so it is not required for `api` or `local` modes to function.

---

## Extension points

### Adding a new data source

1. Add a new method or section inside the relevant `fetch_*` function.
2. Append dicts to `data.connections`, `data.variables`, or `data.secrets`.
3. No changes needed to `export_excel()`.

### Adding a new output format

Replace or extend `export_excel()`. `AirflowData` is a plain dataclass — trivial to serialize to JSON, CSV, etc.

### Adding a new auth method

Insert a new block in `fetch_api()` before the HTTP Basic fallback (step 3). Set `authed = True` and configure `session.headers` or `session.auth` accordingly.
