"""Pytest config: ensure the project root is on sys.path so `src` imports."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
