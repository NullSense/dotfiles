## Phase 3 release — hyprwhspr-ai v0.2

Phase 3 ships a **task-first AI menu** and Gemma-backed OCR. Performance numbers below.

### Performance

| Operation | Cold (ms) | Warm (ms) | Notes |
|---|---|---|---|
| ping | 12 | 3 | healthcheck |
| rewrite | 1820 | 251 | post-dictation |
| ocr (region) | 2140 | 1180 | Gemma vision |
| translate | 3250 | 612 | NLLB-200 |

### Code sample

```python
async def rewrite(self, text: str) -> RewriteResult:
    if not text.strip():
        return RewriteResult(text="", fell_back=False)
    window = await self._windows.current()
    return await self._call_llm(prompt, user)
```

Key wins: *unified daemon ops*, `--mode plain` for translate, and **temperature=0** for OCR determinism.
