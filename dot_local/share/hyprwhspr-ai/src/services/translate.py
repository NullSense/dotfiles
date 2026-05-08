"""Translation service — NLLB-backed.

Resolves a target language (human name or NLLB code) to an NLLB BCP-47
code, then dispatches to NLLBClient. Source defaults to English; we
don't auto-detect today (NLLB doesn't, and our use case is mostly
EN→other anyway).
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from ..nllb import NLLBClient, NLLBUnavailable
from .vision import VisionService


log = logging.getLogger(__name__)


# Human name (lowercased) → NLLB BCP-47 code. Covers the 35 first-class
# NLLB languages plus common ones that fall out of pre-training data.
_LANG_CODES: dict[str, str] = {
    "english": "eng_Latn", "german": "deu_Latn", "lithuanian": "lit_Latn",
    "latvian": "lav_Latn", "estonian": "est_Latn", "polish": "pol_Latn",
    "russian": "rus_Cyrl", "french": "fra_Latn", "spanish": "spa_Latn",
    "italian": "ita_Latn", "portuguese": "por_Latn", "dutch": "nld_Latn",
    "czech": "ces_Latn", "slovak": "slk_Latn", "hungarian": "hun_Latn",
    "romanian": "ron_Latn", "bulgarian": "bul_Cyrl", "croatian": "hrv_Latn",
    "serbian": "srp_Cyrl", "slovenian": "slv_Latn", "ukrainian": "ukr_Cyrl",
    "greek": "ell_Grek", "turkish": "tur_Latn", "arabic": "arb_Arab",
    "hebrew": "heb_Hebr", "hindi": "hin_Deva", "bengali": "ben_Beng",
    "vietnamese": "vie_Latn", "thai": "tha_Thai", "indonesian": "ind_Latn",
    "malay": "zsm_Latn", "japanese": "jpn_Jpan", "korean": "kor_Hang",
    "chinese": "zho_Hans", "mandarin": "zho_Hans", "cantonese": "yue_Hant",
    "chinese (simplified)": "zho_Hans", "chinese (traditional)": "zho_Hant",
    "swedish": "swe_Latn", "norwegian": "nob_Latn", "danish": "dan_Latn",
    "finnish": "fin_Latn", "icelandic": "isl_Latn",
    "persian": "pes_Arab", "farsi": "pes_Arab", "urdu": "urd_Arab",
    "swahili": "swh_Latn", "zulu": "zul_Latn", "afrikaans": "afr_Latn",
}


@dataclass(frozen=True, slots=True)
class TranslateResult:
    text: str
    via: str          # "nllb"
    target_code: str
    took_ms: int


class TranslateError(Exception):
    pass


class TranslateService:
    def __init__(self, nllb: NLLBClient, vision: VisionService):
        self._nllb = nllb
        self._vision = vision

    async def translate(self, text: str, target: str, source: str = "eng_Latn") -> TranslateResult:
        code = self._resolve_target(target)
        t0 = time.perf_counter()
        try:
            out = await self._nllb.translate(text, src=source, tgt=code)
        except NLLBUnavailable as e:
            raise TranslateError(f"NLLB unavailable: {e}") from e
        return TranslateResult(
            text=out, via="nllb", target_code=code,
            took_ms=int((time.perf_counter() - t0) * 1000),
        )

    async def translate_region(self, target: str, source: str = "eng_Latn") -> TranslateResult:
        """Capture region → Gemma OCR → NLLB translate."""
        code = self._resolve_target(target)
        t0 = time.perf_counter()
        # Reuse VisionService for region capture + OCR.
        from .vision import _capture_region, _cleanup  # local import — cycle safety
        img = await _capture_region()
        if img is None:
            raise TranslateError("region capture cancelled")
        try:
            ocr_result = await self._vision.ocr(img)
        finally:
            _cleanup(img)
        if not ocr_result.text.strip():
            raise TranslateError("OCR returned empty text")
        try:
            out = await self._nllb.translate(ocr_result.text, src=source, tgt=code)
        except NLLBUnavailable as e:
            raise TranslateError(f"NLLB unavailable: {e}") from e
        return TranslateResult(
            text=out, via="nllb", target_code=code,
            took_ms=int((time.perf_counter() - t0) * 1000),
        )

    @staticmethod
    def _resolve_target(target: str) -> str:
        """Map a human name or pass-through NLLB code to a BCP-47 code."""
        target = target.strip()
        # Already an NLLB code? (xxx_Yyyy pattern)
        if (len(target) == 8 and target[3] == "_"
                and target[:3].islower() and target[4].isupper()
                and target[5:].islower()):
            return target
        code = _LANG_CODES.get(target.lower())
        if not code:
            raise TranslateError(f"unknown language: {target!r}")
        return code
