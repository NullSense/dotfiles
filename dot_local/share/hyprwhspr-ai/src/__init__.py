"""hyprwhspr-ai — coordinator daemon for hyprwhspr's AI surface.

Sibling to the hyprwhspr STT daemon. Owns all interaction with LM Studio
and the NLLB translation server, replacing the bash glue scripts that
were previously calling them independently.

Design: one async daemon, thin CLI client over a Unix socket. State
lives in process memory; serialization via asyncio.Lock; no flock
files, no /run/user/.cache files, no warmup timer.
"""

__version__ = "0.1.0"
