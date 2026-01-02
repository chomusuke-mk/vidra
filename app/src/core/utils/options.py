from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any, Literal, Mapping, Optional, Sequence, Set, Union, cast

ALL_LANGUAGES: list[str] = [
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
    "en",
    "eo",
    "es",
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

ALL_RESOLUTIONS = [
    "144",
    "240",
    "360",
    "480",
    "720",
    "1080",
    "1440",
    "2160",
    "4320",
]

def _empty_str_dict() -> dict[str, str]:
    return {}


def _empty_str_list() -> list[str]:
    return []


SponsorBlockCategory = Literal[
    "sponsor",
    "intro",
    "outro",
    "selfpromo",
    "preview",
    "filler",
    "interaction",
    "music_offtopic",
    "poi_highlight",
    "chapter",
]


def _empty_sponsorblock_list() -> list[SponsorBlockCategory]:
    return []


AUDIO_OPTIONS = Union[Literal["all", "best", "none"], list[str]]
VIDEO_OPTIONS = Union[Literal["all", "best", "none"], str]
SUBTITLE_OPTIONS = Union[Literal["all", "none"], list[str]]


@dataclass
class OptionsConfig:
    # Magic Options ============================================================================
    audio_language: Union[  # Presets para descargar la mejor pista de audio disponible en ciertos idiomas.
        AUDIO_OPTIONS, bool
    ] = False
    video_resolution: Union[  # Presets para descargar la mejor pista de video disponible en ciertas resoluciones.
        VIDEO_OPTIONS, bool
    ] = False
    video_subtitles: Union[  # Presets para descargar subtítulos en ciertos idiomas.
        SUBTITLE_OPTIONS, bool
    ] = False
    # General Options ===========================================================================
    # // General Options ===========================================================================
    # Ignora errores de descarga y continúa con el siguiente video.
    ignore_errors: bool = True
    # Detiene el proceso de descarga si ocurre un error.
    abort_on_error: bool = False
    use_extractors: Union[  # Nombres de extractores a usar (separados por coma).("all","default",expresión regular)
        Literal["all", "default"], str, bool
    ] = "all"
    # Lista los videos de una playlist sin descargarlos.
    flat_playlist: bool = False
    # Descarga las transmisiones en vivo desde el inicio, si es compatible.
    live_from_start: bool = True
    wait_for_video: Union[  # Espera a que un video programado esté disponible antes de descargarlo.
        bool, int
    ] = False
    # Marca el video como visto (si el sitio lo soporta).
    mark_watched: bool = False
    # Network Options ===========================================================================
    # Proxy HTTP/HTTPS/SOCKS. Ejemplo: socks5://user:pass@127.0.0.1:1080
    proxy: str = ""
    # Tiempo máximo de espera para conexiones (segundos).
    socket_timeout: int = 15
    # Dirección IP del cliente para realizar la conexión.
    source_address: str = ""
    # Cliente a emular (chrome, firefox, edge, etc.).
    impersonate: Union[str, bool] = False
    force_ipv4: bool = False  # Fuerza el uso de IPv4.
    force_ipv6: bool = False  # Fuerza el uso de IPv6.
    # Permite usar URLs locales (file://). Desactivado por seguridad.
    enable_file_urls: bool = False
    # // Geo-restriction ===========================================================================
    # Proxy usado para verificar IP en contenido con restricciones geográficas.
    geo_verification_proxy: str = ""
    # Valor del encabezado HTTP “X-Forwarded-For” para simular ubicación.
    xff: str = ""
    # // Workarounds ===============================================================================
    # Usa conexión HTTP en lugar de HTTPS (solo YouTube).
    prefer_insecure: bool = False
    add_headers: dict[str, str] = field(
        default_factory=_empty_str_dict
    )  # Encabezados HTTP personalizados.
    cookies: Union[  # Archivo Netscape de cookies para autenticación.
        str, bool
    ] = False
    cookies_from_browser: Union[  # Carga cookies directamente de un navegador instalado.
        bool,
        Literal[
            "brave",
            "chrome",
            "chromium",
            "edge",
            "firefox",
            "opera",
            "safari",
            "vivaldi",
            "whale",
        ],
    ] = False
    # // Authentication Options ====================================================================
    username: str = ""  # Usuario o correo para autenticación.
    password: str = ""  # Contraseña del usuario.
    # Código 2FA (autenticación de dos factores).
    twofactor: str = ""
    # Contraseña específica de video (si aplica).
    video_password: str = ""
    # Video Selection ===========================================================================
    # Permite combinar múltiples streams de video.
    video_multistreams: bool = True
    # Permite combinar múltiples streams de audio.
    audio_multistreams: bool = True
    merge_output_format: Literal[  # Formato final para mezclar (“mp4”, “mkv”, “webm”, etc.).
        "avi", "flv", "mkv", "mov", "mp4", "webm"
    ] = "mkv"
    # // Post-Processing Options ===================================================================
    audio_format: Literal[  # Formato del audio convertido (“mp3”, “flac”, “opus”, etc.).
        "best", "aac", "alac", "flac", "m4a", "mp3", "opus", "vorbis", "wav"
    ] = "best"
    # Convierte los videos descargados a audio (usa ffmpeg).
    extract_audio: bool = False
    audio_quality: Literal[  # Calidad del audio (0 mejor, 10 peor).
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
    ] = 0
    remux_video: Union[
        Literal[  # Cambia el contenedor del video sin recodificar.
            "avi",
            "flv",
            "gif",
            "mkv",
            "mov",
            "mp4",
            "webm",
            "aac",
            "aiff",
            "alac",
            "flac",
            "m4a",
            "mka",
            "mp3",
            "ogg",
            "opus",
            "vorbis",
            "wav",
        ],
        bool,
    ] = False
    # Inserta subtítulos en el archivo final.
    embed_subs: bool = True
    # Inserta miniaturas en el archivo final.
    embed_thumbnail: bool = True
    # Inserta metadatos en el archivo final.
    embed_metadata: bool = True
    # Inserta capítulos en el archivo final.
    embed_chapters: bool = True
    # Inserta infojson en el archivo final.
    embed_info_json: bool = True
    # // Video Format Options ======================================================================
    # Código de formato o expresión para selección (ver “FORMAT SELECTION”).
    format: list[str] = field(
        default_factory=lambda: [
            "bestvideo+bestaudio",
            "best",
        ]
    )
    # Escribe metadatos en atributos extendidos del sistema.
    xattrs: bool = False
    fixup: Literal[  # Corrige errores conocidos del archivo (“never”, “warn”, “force”).
        "never", "warn", "detect_or_warn", "force"
    ] = "force"
    # Ruta al ejecutable de ffmpeg o ffprobe.
    ffmpeg_location: str = ""
    convert_thumbnails: Literal[  # Convierte miniaturas al formato indicado (“jpg”, “png”, “webp”).
        "jpg", "png", "webp"
    ] = "webp"
    # // Subtitle Options ==========================================================================
    # Descarga subtítulos manuales disponibles.----------
    write_subs: bool = False
    # Descarga subtítulos generados automáticamente.-----
    write_auto_subs: bool = False
    # Formato preferido de subtítulos (“srt”, “vtt”, “ass”, etc.).
    sub_format: str = "srt"
    # Idiomas de subtítulos a descargar (“en”, “es”, “all”, etc.).
    sub_langs: list[str] = field(default_factory=_empty_str_list)
    # Download Options ==========================================================================
    output: list[str] = field(
        default_factory=lambda: ["title", "-", "artist", ".", "ext"]
    )
    paths: dict[str, str] = field(default_factory=_empty_str_dict)
    # Ruta de archivo donde registrar los IDs descargados, para evitar duplicados.
    download_archive: Union[bool, str] = False
    # Indica si se descarga la lista completa (True) o solo un video (False).
    playlist: bool = True
    # Especifica qué videos de la playlist descargar (índices o rangos).
    # Ejemplo: "1:3,5,7" descarga los ítems 1,2,3,5 y 7.
    playlist_items: str = ""
    # Fragmentos simultáneos a descargar (por defecto 1).
    concurrent_fragments: int = 1
    # Detiene la descarga si se encuentra un archivo ya existente.
    break_on_existing: bool = False
    skip_playlist_after_errors: Union[  # Número máximo de errores permitidos antes de saltar el resto de la playlist.
        int, bool
    ] = False
    retries: Union[  # Reintentos en caso de error (por defecto 10).
        int, Literal["infinite"]
    ] = 10
    file_access_retries: Union[  # Reintentos por error de acceso a archivo (por defecto 3).
        int, Literal["infinite"]
    ] = 5
    fragment_retries: Union[  # Reintentos por fragmento fallido (por defecto 10).
        int, Literal["infinite"]
    ] = 10
    extractor_retries: Union[  # NUEVO            #Reintentos en caso de error en el extractor (por defecto 3).
        int, Literal["infinite"]
    ] = 3
    # Cancela la descarga si algún fragmento no está disponible.
    abort_on_unavailable_fragments: bool = False
    # Mantiene los fragmentos descargados tras finalizar.
    keep_fragments: bool = False
    # // Filesystem Options ========================================================================
    batch_file: Union[  # Archivo con URLs a descargar (una por línea). "-" usa stdin.
        str, bool
    ] = False
    # Sobrescribe archivos existentes (por defecto True).
    force_overwrites: bool = True
    # // Thumbnail Options =========================================================================
    # Guarda la miniatura del video en disco.
    write_thumbnail: bool = False
    # // SponsorBlock Options ======================================================================
    sponsorblock_mark: list[SponsorBlockCategory] = field(
        default_factory=_empty_sponsorblock_list
    )
    # // Extractor Options =========================================================================
    # Límite de velocidad, por ejemplo "500K" o "4.2M".
    limit_rate: str = ""


def build_options_config(
    payload: Mapping[str, Any] | None,
) -> Optional[OptionsConfig]:
    if not payload:
        return None
    params = OptionsConfig()
    has_assignment = False
    for key, value in payload.items():
        normalized = _normalize_option_value(key, value)
        if normalized is None:
            continue
        if hasattr(params, key):
            setattr(params, key, normalized)
            has_assignment = True
    return params if has_assignment else None


def _normalize_option_value(key: str, value: Any) -> Any:
    if value is None:
        return None
    if key == "format":
        return _normalize_format_option(value)
    if key == "output":
        return _normalize_output_option(value)
    return value


def _normalize_format_option(value: Any) -> Optional[list[str]]:
    tokens: list[str] = []

    def _append_parts(text: str) -> None:
        stripped = text.strip()
        if not stripped:
            return
        if "/" in stripped:
            for part in stripped.split("/"):
                part = part.strip()
                if part:
                    tokens.append(part)
        else:
            tokens.append(stripped)

    if isinstance(value, str):
        _append_parts(value)
    elif isinstance(value, Sequence) and not isinstance(value, (str, bytes)):
        sequence_value = cast(Sequence[object], value)
        for entry in sequence_value:
            if entry is None:
                continue
            _append_parts(str(entry))
    else:
        _append_parts(str(value))

    return tokens or None


def _normalize_output_option(value: Any) -> Optional[list[str]]:
    normalized: list[str] = []

    def _append(text: str) -> None:
        stripped = text.strip()
        if stripped:
            normalized.append(stripped)

    if isinstance(value, str):
        _append(value)
    elif isinstance(value, Sequence) and not isinstance(value, (str, bytes)):
        sequence_value = cast(Sequence[object], value)
        for entry in sequence_value:
            if entry is None:
                continue
            _append(str(entry))
    else:
        _append(str(value))

    return normalized or None


def parse_options(
    # Una o varias URLs de los videos o listas de reproducción a descargar.
    urls: list[str],
    params: Optional[OptionsConfig] = None,
) -> list[str]:
    params = params or OptionsConfig()
    audio_language = params.audio_language
    video_resolution = params.video_resolution
    video_subtitles = params.video_subtitles

    ignore_errors = params.ignore_errors
    abort_on_error = params.abort_on_error
    use_extractors = params.use_extractors
    flat_playlist = params.flat_playlist
    live_from_start = params.live_from_start
    wait_for_video = params.wait_for_video
    mark_watched = params.mark_watched

    proxy = params.proxy
    socket_timeout = params.socket_timeout
    source_address = params.source_address
    impersonate = params.impersonate
    force_ipv4 = params.force_ipv4
    force_ipv6 = params.force_ipv6
    enable_file_urls = params.enable_file_urls

    geo_verification_proxy = params.geo_verification_proxy
    xff = params.xff

    prefer_insecure = params.prefer_insecure
    add_headers = params.add_headers
    cookies = params.cookies
    cookies_from_browser = params.cookies_from_browser

    username = params.username
    password = params.password
    twofactor = params.twofactor
    video_password = params.video_password

    video_multistreams = params.video_multistreams
    audio_multistreams = params.audio_multistreams
    merge_output_format = params.merge_output_format

    audio_format = params.audio_format
    extract_audio = params.extract_audio
    audio_quality = params.audio_quality
    remux_video = params.remux_video
    embed_subs = params.embed_subs
    embed_thumbnail = params.embed_thumbnail
    embed_metadata = params.embed_metadata
    embed_chapters = params.embed_chapters
    embed_info_json = params.embed_info_json

    format = params.format
    xattrs = params.xattrs
    fixup = params.fixup
    ffmpeg_location = params.ffmpeg_location
    convert_thumbnails = params.convert_thumbnails

    write_subs = params.write_subs
    write_auto_subs = params.write_auto_subs
    sub_format = params.sub_format
    sub_langs = params.sub_langs

    output = params.output
    paths = params.paths
    download_archive = params.download_archive
    playlist = params.playlist
    playlist_items = params.playlist_items
    concurrent_fragments = params.concurrent_fragments
    break_on_existing = params.break_on_existing
    skip_playlist_after_errors = params.skip_playlist_after_errors
    retries = params.retries
    file_access_retries = params.file_access_retries
    fragment_retries = params.fragment_retries
    extractor_retries = params.extractor_retries
    abort_on_unavailable_fragments = params.abort_on_unavailable_fragments
    keep_fragments = params.keep_fragments

    batch_file = params.batch_file
    force_overwrites = params.force_overwrites

    write_thumbnail = params.write_thumbnail

    sponsorblock_mark = params.sponsorblock_mark

    limit_rate = params.limit_rate

    # --- begin original logic (adapted to use locals above) ---

    comando: list[str] = []
    format_options: list[str] = []
    user_format_options: list[str] = []
    effective_sub_langs: Optional[list[str]]
    effective_sub_langs = list(sub_langs)
    user_format_options = [str(item).strip() for item in format if str(item).strip()]
    video_multistreams_enabled = bool(video_multistreams)
    audio_multistreams_enabled = bool(audio_multistreams)

    video_selectors: list[str] = []
    audio_selectors: list[str] = []
    audio_none_requested = audio_language == "none"

    if video_subtitles:
        effective_sub_langs = []
        if video_subtitles == "all":
            for lang in ALL_LANGUAGES:
                effective_sub_langs.append(f"{lang}.*")
        elif isinstance(video_subtitles, list):
            for lang in video_subtitles:
                effective_sub_langs.append(f"{lang}.*")

    if extract_audio:
        format_options = ["bestaudio/best[acodec!=none]"]
        effective_sub_langs = []
        embed_subs = False
        write_subs = False
        write_auto_subs = False
    else:
        if video_resolution:
            video_multistreams_enabled = True
            if video_resolution == "all":
                video_selectors = [
                    f"bestvideo[height<={res}]"
                    for res in sorted(ALL_RESOLUTIONS, key=int, reverse=True)
                ]
            elif video_resolution == "best" or video_resolution is True:
                video_selectors = ["bestvideo"]
            elif video_resolution == "none":
                video_selectors = ["bestvideo[height=0]"]
            else:
                seen_resolutions: Set[str] = set()
                selector = f"bestvideo[height<={str(video_resolution)}]"
                if selector not in seen_resolutions:
                    video_selectors.append(selector)
                    seen_resolutions.add(selector)
        if not video_selectors:
            video_selectors = ["bestvideo"]

        if audio_language:
            audio_multistreams_enabled = True
            if audio_language == "all":
                audio_selectors = [
                    f"bestaudio[acodec!=none][language^={lang}]"
                    for lang in ALL_LANGUAGES
                ]
            elif audio_language == "best" or audio_language is True:
                audio_selectors = ["bestaudio[acodec!=none]"]
            elif audio_none_requested:
                audio_selectors = ["bestaudio[acodec=none]"]
            else:
                seen_languages: Set[str] = set()
                for lang in audio_language:
                    if lang not in seen_languages:
                        audio_selectors.append(
                            f"bestaudio[acodec!=none][language^={lang}]"
                        )
                        seen_languages.add(lang)
                if len(audio_selectors) > 1:
                    audio_multistreams_enabled = True
            if not audio_none_requested and audio_selectors:
                fallback_selector = "bestaudio[acodec!=none]"
                if fallback_selector not in audio_selectors:
                    audio_selectors.append(fallback_selector)
        if not audio_selectors and not audio_none_requested:
            audio_selectors = ["bestaudio[acodec!=none]"]

        derived_formats: list[str] = []
        if audio_selectors:
            for video_selector in video_selectors:
                for audio_selector in audio_selectors:
                    if video_selector and audio_selector:
                        derived_formats.append(f"{video_selector}+{audio_selector}")
                    elif video_selector:
                        derived_formats.append(video_selector)
                    else:
                        derived_formats.append(audio_selector)
        else:
            derived_formats.extend(video_selectors)

        format_options = derived_formats

    merged_formats: list[str] = []
    extra_fallbacks = [] if extract_audio else user_format_options
    for option in format_options + extra_fallbacks:
        option_str = str(option).strip()
        if option_str and option_str not in merged_formats:
            merged_formats.append(option_str)
    format_options = merged_formats

    video_multistreams = video_multistreams_enabled
    audio_multistreams = audio_multistreams_enabled
    # General Options
    if ignore_errors:
        comando.append("--ignore-errors")
    if abort_on_error:
        comando.append("--abort-on-error")
    else:
        comando.append("--no-abort-on-error")
    if use_extractors:
        comando.extend(["--use-extractors", str(use_extractors)])
    if flat_playlist:
        comando.append("--flat-playlist")
    else:
        comando.append("--no-flat-playlist")
    if live_from_start:
        comando.append("--live-from-start")
    else:
        comando.append("--no-live-from-start")
    if not wait_for_video:
        comando.append("--no-wait-for-video")
    elif wait_for_video:
        comando.extend(["--wait-for-video", str(wait_for_video)])
    if mark_watched:
        comando.append("--mark-watched")
    else:
        comando.append("--no-mark-watched")
    # Network Options
    if proxy:
        comando.extend(["--proxy", proxy])
    if socket_timeout:
        comando.extend(["--socket-timeout", str(socket_timeout)])
    if source_address:
        comando.extend(["--source-address", source_address])
    if impersonate:
        comando.extend(["--impersonate", str(impersonate)])
    if force_ipv4:
        comando.append("--force-ipv4")
    if force_ipv6:
        comando.append("--force-ipv6")
    if enable_file_urls:
        comando.append("--enable-file-urls")
    # Geo-restriction
    if geo_verification_proxy:
        comando.extend(["--geo-verification-proxy", geo_verification_proxy])
    if xff:
        comando.extend(["--xff", xff])
    # Video Selection
    if playlist_items:
        comando.extend(["--playlist-items", str(playlist_items)])
    if playlist:
        comando.append("--yes-playlist")
    else:
        comando.append("--no-playlist")
    if download_archive:
        comando.extend(["--download-archive", str(download_archive)])
    if break_on_existing:
        comando.append("--break-on-existing")
    else:
        comando.append("--no-break-on-existing")
    if not isinstance(skip_playlist_after_errors, bool):
        comando.extend(
            ["--skip-playlist-after-errors", str(skip_playlist_after_errors)]
        )
    # Download Options
    if concurrent_fragments:
        comando.extend(["--concurrent-fragments", str(concurrent_fragments)])
    if limit_rate:
        comando.extend(["--limit-rate", str(limit_rate)])
    if retries:
        comando.extend(["--retries", str(retries)])
    if file_access_retries:
        comando.extend(["--file-access-retries", str(file_access_retries)])
    if fragment_retries:
        comando.extend(["--fragment-retries", str(fragment_retries)])
    if abort_on_unavailable_fragments:
        comando.append("--abort-on-unavailable-fragments")
    else:
        comando.append("--skip-unavailable-fragments")
    if keep_fragments:
        comando.append("--keep-fragments")
    # Filesystem Options
    if batch_file is False:
        comando.append("--no-batch-file")
    elif isinstance(batch_file, str) and batch_file:
        comando.extend(["--batch-file", batch_file])
    if paths:
        for k, v in paths.items():
            comando.extend(["-P", f"{k}:{v}"])
    if output:
        nombre = ""
        for i in output:
            if i in [
                "id",
                "title",
                "fulltitle",
                "ext",
                "alt_title",
                "description",
                "display_id",
                "uploader",
                "uploader_id",
                "uploader_url",
                "license",
                "creators",
                "creator",
                "timestamp",
                "upload_date",
                "release_timestamp",
                "release_date",
                "release_year",
                "modified_timestamp",
                "modified_date",
                "channel",
                "channel_id",
                "channel_url",
                "channel_follower_count",
                "channel_is_verified",
                "location",
                "duration",
                "duration_string",
                "view_count",
                "concurrent_view_count",
                "like_count",
                "dislike_count",
                "repost_count",
                "average_rating",
                "comment_count",
                "age_limit",
                "live_status",
                "is_live",
                "was_live",
                "playable_in_embed",
                "availability",
                "media_type",
                "start_time",
                "end_time",
                "extractor",
                "extractor_key",
                "epoch",
                "autonumber",
                "video_autonumber",
                "n_entries",
                "playlist_id",
                "playlist_title",
                "playlist",
                "playlist_count",
                "playlist_index",
                "playlist_autonumber",
                "playlist_uploader",
                "playlist_uploader_id",
                "playlist_channel",
                "playlist_channel_id",
                "playlist_webpage_url",
                "webpage_url",
                "webpage_url_basename",
                "webpage_url_domain",
                "original_url",
                "categories",
                "tags",
                "cast",
                "chapter",
                "chapter_number",
                "chapter_id",
                "series",
                "series_id",
                "season",
                "season_number",
                "season_id",
                "episode",
                "episode_number",
                "episode_id",
                "track",
                "track_number",
                "track_id",
                "artists",
                "artist",
                "genres",
                "genre",
                "composers",
                "composer",
                "album",
                "album_type",
                "album_artists",
                "album_artist",
                "disc_number",
                "section_title",
                "section_number",
                "section_start",
                "section_end",
            ]:
                nombre += f"%({i})s"
            else:
                nombre += i
        comando.extend(["--output", nombre])
    if force_overwrites:
        comando.append("--force-overwrites")
    else:
        comando.append("--no-force-overwrites")
    if cookies is False:
        comando.append("--no-cookies")
    elif isinstance(cookies, str) and cookies:
        comando.extend(["--cookies", cookies])
    if cookies_from_browser is False:
        comando.append("--no-cookies-from-browser")
    elif cookies_from_browser:
        comando.extend(["--cookies-from-browser", str(cookies_from_browser)])
    # Thumbnail Options
    if write_thumbnail:
        comando.append("--write-thumbnail")
    else:
        comando.append("--no-write-thumbnail")
    # Workarounds
    if prefer_insecure:
        comando.append("--prefer-insecure")
    if add_headers:
        for k, v in add_headers.items():
            comando.extend(["--add-headers", f"{k}: {v}"])
    # Video Format Options
    if format_options:
        comando.extend(["--format", "/".join(format_options)])
    if video_multistreams:
        comando.append("--video-multistreams")
    if audio_multistreams:
        comando.append("--audio-multistreams")
    if merge_output_format:
        comando.extend(["--merge-output-format", merge_output_format])
    # Subtitle Options
    if write_subs:
        comando.append("--write-subs")
    else:
        comando.append("--no-write-subs")
    if write_auto_subs:
        comando.append("--write-auto-subs")
    else:
        comando.append("--no-write-auto-subs")
    if sub_format:
        comando.extend(["--sub-format", str(sub_format)])
    if effective_sub_langs:
        comando.extend(["--sub-langs", ",".join(effective_sub_langs)])
    # Authentication Options
    if username:
        comando.extend(["--username", username])
    if password:
        comando.extend(["--password", password])
    if twofactor:
        comando.extend(["--twofactor", twofactor])
    if video_password:
        comando.extend(["--video-password", video_password])
    # Post-processing Options
    if extract_audio:
        comando.append("--extract-audio")
    if audio_format:
        comando.extend(["--audio-format", str(audio_format)])
    if audio_quality:
        comando.extend(["--audio-quality", str(audio_quality)])
    if remux_video:
        comando.extend(["--remux-video", str(remux_video)])
    if embed_subs:
        comando.append("--embed-subs")
    if embed_thumbnail:
        comando.append("--embed-thumbnail")
    if embed_metadata:
        comando.append("--embed-metadata")
    if embed_chapters:
        comando.append("--embed-chapters")
    if embed_info_json:
        comando.append("--embed-info-json")
    if xattrs:
        comando.append("--xattrs")
    if fixup:
        comando.extend(["--fixup", str(fixup)])
    if ffmpeg_location:
        comando.extend(["--ffmpeg-location", str(ffmpeg_location)])
    if convert_thumbnails:
        comando.extend(["--convert-thumbnails", str(convert_thumbnails)])
    # SponsorBlock Options
    if sponsorblock_mark:
        marks = [str(item) for item in sponsorblock_mark if item]
        if marks:
            comando.extend(["--sponsorblock-mark", ",".join(marks)])
    # Extractor Options
    if extractor_retries:
        comando.extend(["--extractor-retries", str(extractor_retries)])
    comando.extend([str(url) for url in urls])
    normalized: list[str] = []
    for item in comando:
        if isinstance(item, (list, tuple, set)):
            normalized.extend(str(element) for element in item)
        else:
            normalized.append(str(item))
    print(f"Parsed options: {normalized}")  # TODO remove debug print
    return normalized


__all__ = ["parse_options", "OptionsConfig", "build_options_config"]
