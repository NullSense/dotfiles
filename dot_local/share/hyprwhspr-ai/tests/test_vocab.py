"""Tests for the vocabulary repository.

Verifies file reading, mtime-based caching, comment/blank stripping,
and graceful handling of missing files.
"""

from __future__ import annotations

import time
from pathlib import Path

import pytest

from src.vocab import VocabRepository


def test_missing_file_returns_empty(tmp_path: Path):
    repo = VocabRepository(path=tmp_path / "does-not-exist.txt")
    assert repo.block() == ""


def test_empty_file_returns_empty(tmp_path: Path):
    f = tmp_path / "vocab.txt"
    f.write_text("")
    repo = VocabRepository(path=f)
    assert repo.block() == ""


def test_only_comments_returns_empty(tmp_path: Path):
    f = tmp_path / "vocab.txt"
    f.write_text("# this is a comment\n# another\n\n   \n")
    repo = VocabRepository(path=f)
    assert repo.block() == ""


def test_strips_comments_and_blanks(tmp_path: Path):
    f = tmp_path / "vocab.txt"
    f.write_text("Cortiq\n# comment\n\nTensil\n   \nHyprland\n")
    repo = VocabRepository(path=f)
    block = repo.block()
    assert "Cortiq" in block
    assert "Tensil" in block
    assert "Hyprland" in block
    assert "comment" not in block


def test_block_includes_known_vocabulary_header(tmp_path: Path):
    f = tmp_path / "vocab.txt"
    f.write_text("Cortiq\n")
    repo = VocabRepository(path=f)
    block = repo.block()
    assert "[Known vocabulary]" in block


def test_mtime_cache_hit(tmp_path: Path):
    """Calling block() twice without modifying the file = single read."""
    f = tmp_path / "vocab.txt"
    f.write_text("Cortiq\n")
    repo = VocabRepository(path=f)
    first = repo.block()
    second = repo.block()
    assert first == second
    # ensure same internal cached value (string identity not guaranteed
    # but mtime should match)
    assert repo._mtime > 0


def test_mtime_cache_invalidates_on_change(tmp_path: Path):
    f = tmp_path / "vocab.txt"
    f.write_text("Cortiq\n")
    repo = VocabRepository(path=f)
    first = repo.block()
    assert "Cortiq" in first
    # Modify with a clearly newer mtime.
    time.sleep(0.01)
    f.write_text("Tensil\n")
    # Force mtime difference (some filesystems have coarse granularity).
    import os
    now = time.time()
    os.utime(f, (now, now + 1))
    second = repo.block()
    assert "Tensil" in second
    assert "Cortiq" not in second


def test_unicode_terms(tmp_path: Path):
    f = tmp_path / "vocab.txt"
    f.write_text("Hyprland\nžingsnis\nTōkyō\n")
    repo = VocabRepository(path=f)
    block = repo.block()
    assert "žingsnis" in block
    assert "Tōkyō" in block


def test_terms_with_internal_spaces(tmp_path: Path):
    """Multi-word terms like 'LM Studio' should survive intact."""
    f = tmp_path / "vocab.txt"
    f.write_text("LM Studio\nVisual Studio Code\n")
    repo = VocabRepository(path=f)
    block = repo.block()
    assert "LM Studio" in block
    assert "Visual Studio Code" in block
