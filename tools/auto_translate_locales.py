import hashlib
import json
import os
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import TypedDict

import jsonc  # type: ignore[import-untyped]
from deep_translator import GoogleTranslator  # type: ignore[import]
from tqdm.auto import tqdm  # type: ignore


class LocaleParams(TypedDict):
    input_file: Path
    input_file_hash: Path
    output_file: Path
    output_file_hash: Path
    locale: str


CURRENT_DIR = Path(__file__).resolve().parent
ROOT_DIR = Path(__file__).resolve().parents[1]
BASE_LOCALE = "en"
LOCALES_DIR = ROOT_DIR / "i18n"
HASHES_DIR = CURRENT_DIR / "hashes"
BASE_LOCALE_FILE = LOCALES_DIR / f"{BASE_LOCALE}.jsonc"
BASE_LOCALE_HASH = HASHES_DIR / f"{BASE_LOCALE}.hash.json"

# --- NUEVO: Diccionario para corregir discrepancias con Google Translate ---
# Google usa ciertas variantes BCP-47 específicas.
# Si detectas otro idioma que falla, agrégalo aquí.
GOOGLE_LANG_MAP = {
    "zh": "zh-CN",  # Chino -> Chino Simplificado
    "he": "iw",  # Hebreo -> Google históricamente usa 'iw'
    "jv": "jw",  # Javanés -> Google usa 'jw'
    "nb": "no",  # Noruego Bokmål -> Noruego
    "nn": "no",  # Noruego Nynorsk -> Noruego
    "tw": "ak",  # Twi -> Akan
}
# --------------------------------------------------------------------------

LANGS = [
    "aa",
    "ab",
    "ae",
    "af",
    "ak",
    "am",
    "an",
    "ar",
    "as",
    "av",
    "ay",
    "az",
    "ba",
    "be",
    "bg",
    "bi",
    "bm",
    "bn",
    "bo",
    "br",
    "bs",
    "ca",
    "ce",
    "ch",
    "co",
    "cr",
    "cs",
    "cu",
    "cv",
    "cy",
    "da",
    "de",
    "dv",
    "dz",
    "ee",
    "el",
    "eo",
    "es",
    "en",
    "et",
    "eu",
    "fa",
    "ff",
    "fi",
    "fj",
    "fo",
    "fr",
    "fy",
    "ga",
    "gd",
    "gl",
    "gn",
    "gu",
    "gv",
    "ha",
    "he",
    "hi",
    "ho",
    "hr",
    "ht",
    "hu",
    "hy",
    "hz",
    "ia",
    "id",
    "ie",
    "ig",
    "ii",
    "ik",
    "io",
    "is",
    "it",
    "iu",
    "ja",
    "jv",
    "ka",
    "kg",
    "ki",
    "kj",
    "kk",
    "kl",
    "km",
    "kn",
    "ko",
    "kr",
    "ks",
    "ku",
    "kv",
    "kw",
    "ky",
    "la",
    "lb",
    "lg",
    "li",
    "ln",
    "lo",
    "lt",
    "lu",
    "lv",
    "mg",
    "mh",
    "mi",
    "mk",
    "ml",
    "mn",
    "mr",
    "ms",
    "mt",
    "my",
    "na",
    "nb",
    "nd",
    "ne",
    "ng",
    "nl",
    "nn",
    "no",
    "nr",
    "nv",
    "ny",
    "oc",
    "oj",
    "om",
    "or",
    "os",
    "pa",
    "pi",
    "pl",
    "ps",
    "pt",
    "qu",
    "rm",
    "rn",
    "ro",
    "ru",
    "rw",
    "sa",
    "sc",
    "sd",
    "se",
    "sg",
    "si",
    "sk",
    "sl",
    "sm",
    "sn",
    "so",
    "sq",
    "sr",
    "ss",
    "st",
    "su",
    "sv",
    "sw",
    "ta",
    "te",
    "tg",
    "th",
    "ti",
    "tk",
    "tl",
    "tn",
    "to",
    "tr",
    "ts",
    "tt",
    "tw",
    "ty",
    "ug",
    "uk",
    "ur",
    "uz",
    "ve",
    "vi",
    "vo",
    "wa",
    "wo",
    "xh",
    "yi",
    "yo",
    "za",
    "zh",
    "zu",
]

LOCALES: list[LocaleParams] = [
    {
        "input_file": BASE_LOCALE_FILE,
        "input_file_hash": BASE_LOCALE_HASH,
        "output_file": LOCALES_DIR / f"{code}.jsonc",
        "output_file_hash": HASHES_DIR / f"{code}.hash.json",
        "locale": code,
    }
    for code in LANGS
    if code != BASE_LOCALE
]

os.makedirs(HASHES_DIR, exist_ok=True)
os.makedirs(LOCALES_DIR, exist_ok=True)

# Guardar hash del base locale inicial
with (
    open(BASE_LOCALE_HASH, "w", encoding="utf-8") as f,
    open(BASE_LOCALE_FILE, "r", encoding="utf-8") as input_file,
):
    input_content = jsonc.load(input_file)
    if not isinstance(input_content, dict):
        raise TypeError("Input content is not a dictionary.")
    if not all(
        isinstance(key, str) and isinstance(value, str)
        for key, value in input_content.items()
    ):
        raise ValueError(
            "Input content must be a dictionary of string keys and string values."
        )
    input_hash = {
        key: hashlib.sha256(value.encode("utf-8")).hexdigest()
        for key, value in input_content.items()
    }
    json.dump(input_hash, f, ensure_ascii=False, indent=2)


def translate_lang(
    locale_params: LocaleParams, stop_event: threading.Event, position: int
) -> None:
    if stop_event.is_set():
        return

    if not os.path.exists(locale_params["input_file"]) or not os.path.exists(
        locale_params["input_file_hash"]
    ):
        tqdm.write(
            f"Error: Input file or hash file does not exist for {locale_params['locale']}"
        )
        return

    with locale_params["input_file"].open(encoding="utf-8") as f:
        input_content = jsonc.load(f)
    with locale_params["input_file_hash"].open(encoding="utf-8") as f:
        input_hash = json.load(f)

    if not isinstance(input_content, dict) or not isinstance(input_hash, dict):
        tqdm.write("Error: Input content or hash is not a dictionary.")
        return
    if any(key not in input_hash for key in input_content):
        tqdm.write("Error: Input hash is missing keys from input content.")
        return

    # Leer output o inicializar
    if os.path.exists(locale_params["output_file"]):
        with locale_params["output_file"].open(encoding="utf-8") as f:
            output_content = jsonc.load(f)
    else:
        output_content = {}

    if os.path.exists(locale_params["output_file_hash"]):
        with locale_params["output_file_hash"].open(encoding="utf-8") as f:
            output_hash = json.load(f)
    else:
        output_hash = {}

    if not isinstance(output_content, dict) or not isinstance(output_hash, dict):
        tqdm.write("Error: Output content or hash is not a dictionary.")
        return

    original_locale = locale_params["locale"]
    target_lang = GOOGLE_LANG_MAP.get(original_locale, original_locale)

    try:
        # Si Google no soporta el idioma (ej. "ch" chamorro), esto falla antes de empezar.
        translator = GoogleTranslator(source="en", target=target_lang)
    except Exception as e:
        tqdm.write(
            f"⚠️ [{original_locale.upper()}] Omitido: Idioma '{target_lang}' no soportado o error de red (e)"
        )
        return  # Regresamos aquí. NO fallará el hilo principal, solo omitirá este idioma.

    # Envolvemos el bucle en try-finally para que GUARDE ESTADO siempre al salir
    try:
        for key, value in tqdm(
            input_hash.items(),
            desc=f"[{original_locale.upper()}]",
            unit="key",
            position=position,
            leave=False,
        ):
            if stop_event.is_set():
                break

            if key not in output_hash or output_hash[key] != value:
                try:
                    translated_value = translator.translate(input_content[key])
                    assert translated_value, f"Translation for key '{key}' is empty."
                    output_content[key] = translated_value
                    output_hash[key] = value
                except Exception as e:
                    tqdm.write(f"Error translating '{key}' to {original_locale}: {e}")
    finally:
        with locale_params["output_file_hash"].open("w", encoding="utf-8") as f_hash:
            json.dump(output_hash, f_hash, ensure_ascii=False, indent=2)

        with locale_params["output_file"].open("w", encoding="utf-8") as f_out:
            jsonc.dump(output_content, f_out, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    stop_event = threading.Event()
    max_workers = 6

    print("Iniciando traducciones...")
    print(">>> PRESIONA [Ctrl + C] EN CUALQUIER MOMENTO PARA DETENER Y GUARDAR <<<")

    try:
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = []
            for i, locale_param in enumerate(LOCALES):
                futures.append(
                    executor.submit(
                        translate_lang, locale_param, stop_event, i % max_workers
                    )
                )

            for future in as_completed(futures):
                # Ahora future.result() no colapsará si un idioma falla,
                # porque lo estamos atrapando y retornando de forma segura.
                future.result()

    except KeyboardInterrupt:
        print("\n\n[!] Interrupción detectada (Ctrl+C).")
        print(
            "[!] Solicitando detención a los hilos... Guardando progreso de forma segura..."
        )
        stop_event.set()
    except Exception as e:
        print(f"\n[!] Ocurrió un error inesperado en el hilo principal: {e}")
        stop_event.set()

    print("\nProceso finalizado.")
