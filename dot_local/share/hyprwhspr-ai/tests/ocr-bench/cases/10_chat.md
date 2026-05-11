**nullsense** — Today at 03:41
finally got chandra working alongside gemma in the same lm studio session. `--engine chandra` in the daemon now routes properly

**alex** — Today at 03:43
nice. how much vram is it eating with both loaded?

**nullsense** — Today at 03:43
~11.8GB on the 6750 XT. tight but stable. KV cache at Q8_0 saved about 600MB

**jordan** — Today at 03:44
@nullsense isn't the 6750 XT only 12GB? what happens when you also need the embedder loaded

**nullsense** — Today at 03:46
embedder is tiny (~150MB), it fits. the real ceiling is qwen 35B-A3B which doesn't coexist with gemma at all
