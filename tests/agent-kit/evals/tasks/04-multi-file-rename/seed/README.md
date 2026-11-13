# fetcher

A tiny request formatter driven by a JSON config file.

    python3 -m fetcher config.json http://example.com/

## Configuration

`timeout` is the request timeout in seconds and `retries` the number of retry
attempts. Both are optional. See `config.example.json`.

```json
{
  "timeout": 10,
  "retries": 2
}
```

From Python:

```python
from fetcher.config import load_config

cfg = load_config("config.json")
print(cfg["timeout"])
```
