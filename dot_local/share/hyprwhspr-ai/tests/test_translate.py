"""Tests for translation language code resolution."""

from __future__ import annotations

import pytest

from src.services.translate import TranslateError, TranslateService


# We don't need a real NLLB or vision client to test code resolution.
_RESOLVE = TranslateService._resolve_target  # static, no instance needed


def test_passthrough_nllb_code():
    assert _RESOLVE("eng_Latn") == "eng_Latn"
    assert _RESOLVE("lit_Latn") == "lit_Latn"
    assert _RESOLVE("zho_Hans") == "zho_Hans"


def test_human_name_lower():
    assert _RESOLVE("english") == "eng_Latn"
    assert _RESOLVE("german") == "deu_Latn"
    assert _RESOLVE("lithuanian") == "lit_Latn"


def test_human_name_caps():
    assert _RESOLVE("English") == "eng_Latn"
    assert _RESOLVE("LITHUANIAN") == "lit_Latn"
    assert _RESOLVE("German") == "deu_Latn"


def test_chinese_variants():
    assert _RESOLVE("Chinese") == "zho_Hans"
    assert _RESOLVE("Mandarin") == "zho_Hans"
    assert _RESOLVE("chinese (simplified)") == "zho_Hans"
    assert _RESOLVE("Chinese (Traditional)") == "zho_Hant"
    assert _RESOLVE("Cantonese") == "yue_Hant"


def test_aliases():
    """Persian/Farsi → same code."""
    assert _RESOLVE("Persian") == _RESOLVE("Farsi") == "pes_Arab"


def test_baltic_languages():
    """The whole reason we picked NLLB."""
    assert _RESOLVE("Lithuanian") == "lit_Latn"
    assert _RESOLVE("Latvian") == "lav_Latn"
    assert _RESOLVE("Estonian") == "est_Latn"


def test_unknown_language_raises():
    with pytest.raises(TranslateError) as excinfo:
        _RESOLVE("Klingon")
    assert "klingon" in str(excinfo.value).lower()


def test_whitespace_stripped():
    assert _RESOLVE("  English  ") == "eng_Latn"


def test_partial_nllb_code_not_treated_as_pass_through():
    """'eng' alone shouldn't be treated as a code (would skip lookup)."""
    with pytest.raises(TranslateError):
        _RESOLVE("eng")


def test_malformed_code_falls_through_to_lookup():
    """An NLLB-shaped string that doesn't actually exist in NLLB still
    passes through (we trust the user to type valid codes)."""
    # Pattern matches: 3 lowercase + _ + 4 char with first uppercase.
    # 'xxx_Yyyy' is structurally valid even if not a real NLLB code.
    assert _RESOLVE("xxx_Yyyy") == "xxx_Yyyy"
