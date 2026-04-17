# get_airflow_vars

Extracts **connections**, **variables**, and **secrets/config** from an Apache Airflow instance and saves them to a formatted `.xlsx` file.

Supports three extraction modes:

| Mode | When to use |
|------|-------------|
| `api` | Remote Airflow instance accessible over HTTP/S |
| `local` | Airflow installed on the current machine |
| `docker` | Airflow running in a local Docker container |

---

## Requirements

- Python ≥ 3.11
- [uv](https://github.com/astral-sh/uv) — dependencies are declared inline, no `pip install` needed

---

## Remote execution (one-liner)

Run directly from a URL without cloning. Replace `MushroomSquad/airparse` with your actual GitHub path.

### API mode — password auth

```bash
curl -fsSL https://raw.githubusercontent.com/MushroomSquad/airparse/main/install.sh | bash -s -- \
    --mode api \
    --url https://airflow.example.com \
    --user admin \
    --password secret \
    --output export.xlsx
```

### API mode — browser cookie (SSO/OAuth/LDAP)

```bash
curl -fsSL https://raw.githubusercontent.com/MushroomSquad/airparse/main/install.sh | bash -s -- \
    --mode api \
    --url https://airflow.example.com \
    --cookie "session=abc123..." \
    --output export.xlsx
```

### Local mode

```bash
curl -fsSL https://raw.githubusercontent.com/MushroomSquad/airparse/main/install.sh | bash -s -- \
    --mode local \
    --airflow-home ~/airflow \
    --output export.xlsx
```

### Docker mode

```bash
curl -fsSL https://raw.githubusercontent.com/MushroomSquad/airparse/main/install.sh | bash -s -- \
    --mode docker \
    --container airflow-webserver \
    --output export.xlsx
```

> **Tip:** Override script URL via env var:
> ```bash
> GET_AIRFLOW_VARS_URL="https://example.com/get_airflow_vars.py" \
>   curl -fsSL https://example.com/install.sh | bash -s -- --mode local
> ```

The wrapper script will:
1. Check if `uv` is installed; install it automatically if missing
2. Download and run `get_airflow_vars.py` with the provided arguments
3. Clean up temporary files on exit

---

## Quick start (local)

```bash
# Remote instance — password auth
uv run get_airflow_vars.py --mode api \
    --url https://airflow.example.com \
    --user admin --password secret \
    --output export.xlsx

# Remote instance — browser session cookie (SSO / OAuth environments)
uv run get_airflow_vars.py --mode api \
    --url https://airflow.example.com \
    --cookie "session=abc123..." \
    --output export.xlsx

# Local Airflow installation
uv run get_airflow_vars.py --mode local --output export.xlsx

# Docker container
uv run get_airflow_vars.py --mode docker \
    --container airflow-webserver \
    --output export.xlsx
```

---

## CLI reference

```
usage: get_airflow_vars.py --mode {api,local,docker} [options]

options:
  --mode       api | local | docker   (required)
  --output     output .xlsx path      (default: airflow_export.xlsx)

API mode:
  --url        Airflow base URL, e.g. https://airflow.example.com
  --user       Username                 (default: admin)
  --password   Password                 (default: admin)
  --cookie     Raw browser cookie string — bypasses login entirely
               e.g. "session=3eddfc93-..."

Local mode:
  --airflow-home   AIRFLOW_HOME path   (default: ~/airflow)

Docker mode:
  --container      Container name or ID  (required)
  --docker-home    AIRFLOW_HOME inside the container (default: /opt/airflow)
```

---

## Authentication (API mode)

The script attempts authentication in this priority order:

1. **Browser cookie** (`--cookie`) — highest priority, skips all login flows. Use this when the instance is behind SSO/OAuth/LDAP that blocks programmatic login.
2. **JWT token** — tries Airflow 3.x `/auth/token` and then `/api/v1/security/login`.
3. **Web-form login** — POSTs credentials to `/login`, extracts CSRF token automatically.
4. **HTTP Basic** — last resort fallback.

### Getting a browser cookie

If password auth fails with 403 (common with SSO):

1. Log in via your browser normally.
2. Open DevTools → Network tab → click any request to the Airflow host.
3. Find the `Cookie:` request header — copy the full value.
4. Pass it with `--cookie "session=..."`.

> **Note:** Browser session cookies expire. If you get 403 again after a while, grab a fresh cookie.

---

## Output format

The `.xlsx` file contains four sheets:

### Connections
| conn_id | conn_type | host | port | schema | login | password | extra |
|---------|-----------|------|------|--------|-------|----------|-------|

> ⚠️ **API mode limitation:** Airflow REST API **does not return connection passwords** — the `password` column will be empty. This is a security restriction in Airflow itself. Use `local` or `docker` mode to extract passwords.

### Variables
| key | value | description |
|-----|-------|-------------|

### Secrets\_Config
| section | key | value | source |
|---------|-----|-------|--------|

Sources:
- `airflow_config` — from the REST API `/config` endpoint (API mode)
- `/path/to/airflow.cfg` — parsed config file (local mode)
- `docker:<container>:<path>/airflow.cfg` — config from container (docker mode)
- `docker:<container>:env` — sensitive env vars from container (docker mode)

### Summary
Row counts for each of the three data sheets.

---

## Mode details

### `api` mode

Uses the Airflow REST API. Auto-detects the API version by probing `/api/v2` (Airflow 3.x) then `/api/v1` (Airflow 2.x). Paginates automatically — no limit on the number of records.

Fetches:
- `GET /connections` — all connections (paginated)
- `GET /variables` — all variables (paginated)
- `GET /config` — full `airflow.cfg` config (requires Admin role; skipped with 403 otherwise)

> ⚠️ **Passwords not available:** Airflow API masks connection passwords for security. The `password` field will always be empty in API mode. Use `local` or `docker` mode if you need passwords.

### `local` mode

Runs `airflow` CLI commands on the current machine:
- `airflow connections export /dev/stdout --file-format json`
- `airflow variables export /dev/stdout`
- Reads `$AIRFLOW_HOME/airflow.cfg` directly

Use `--airflow-home` if your `AIRFLOW_HOME` is not the default `~/airflow`.

### `docker` mode

Connects to a running container via the Docker SDK and executes the same CLI commands inside it. Also extracts sensitive environment variables (those containing `SECRET`, `PASSWORD`, `TOKEN`, `KEY`, `AIRFLOW__`, or `FERNET` in their name).

Requires Docker to be running and the Docker socket accessible.

---

## Permissions

What you can extract depends on the role assigned to the authenticated user:

| Data | Required role |
|------|---------------|
| Connections | `Viewer` or higher |
| Variables | `Viewer` or higher |
| Config (`/config`) | `Admin` |

If an endpoint returns 403, it is skipped and logged — the script does not abort.
