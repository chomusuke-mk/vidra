from .manager_protocols import DownloadManagerProtocol


class JobLogger:
    """Proxy logger that records messages against a download job."""

    def __init__(self, manager: DownloadManagerProtocol, job_id: str) -> None:
        self.manager = manager
        self.job_id = job_id

    def debug(self, message: str) -> None:
        self._log("debug", message)

    def info(self, message: str) -> None:
        self._log("info", message)

    def warning(
        self, message: str, *, once: bool | None = None, only_once: bool | None = None
    ) -> None:
        self._log("warning", message)

    def error(self, message: str) -> None:
        self._log("error", message)

    def stdout(self, message: str) -> None:
        self._log("stdout", message)

    def stderr(self, message: str) -> None:
        self._log("stderr", message)

    def _log(self, level: str, message: str) -> None:
        text = str(message)
        if not text:
            return
        self.manager.append_log(self.job_id, level, text)
