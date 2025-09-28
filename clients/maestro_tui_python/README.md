# Maestro TUI (Python/Textual)

- Python 3.10+
- No auto-installs. Install explicitly:

```
cd clients/maestro_tui_python
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\\Scripts\\activate
pip install -e .[dev]
```

## Config

Create `~/.the_maestro/config.json`:

```
{ "api_host": "http://127.0.0.1:4000", "api_key": "0000000000000000" }
```

## Run

```
python -m maestro_tui.app
```

## Test

```
pytest -q
```

