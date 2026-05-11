### Async retry with exponential backoff

```python
import asyncio
from typing import Awaitable, Callable, TypeVar

T = TypeVar("T")

async def retry_with_backoff(
    op: Callable[[], Awaitable[T]],
    *,
    max_attempts: int = 5,
    base_delay: float = 0.5,
    max_delay: float = 10.0,
) -> T:
    """Retry an async op with exponential backoff. Raises the last exception
    after max_attempts."""
    last_exc: Exception | None = None
    for attempt in range(max_attempts):
        try:
            return await op()
        except Exception as e:
            last_exc = e
            if attempt == max_attempts - 1:
                raise
            delay = min(base_delay * (2 ** attempt), max_delay)
            await asyncio.sleep(delay)
    assert last_exc is not None
    raise last_exc
```

### Usage

```python
result = await retry_with_backoff(
    lambda: client.fetch("https://api.example.com/v1/items"),
    max_attempts=3,
    base_delay=0.25,
)
```
