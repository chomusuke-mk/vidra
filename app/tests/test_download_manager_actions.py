from __future__ import annotations

import threading
from pathlib import Path
from typing import Callable, cast

import pytest

from src.config import JobKind, JobStatus
from src.core import Manager as CoreManager
from src.download.job_log_store import JobLogStore
from src.download.job_options_store import JobOptionsStore
from src.download.manager import DownloadManager
from src.download.models import DownloadJob
from src.download.playlist_entry_store import PlaylistEntryStore
from src.models.download.playlist_entry_error import PlaylistEntryError
from src.download.state_store import DownloadStateStore
from src.download.stages import DownloadStage
from src.models.shared.payloads import (
    PlaylistEntryMetadataPayload,
    PlaylistMetadataPayload,
)
from src.socket_manager import SocketManager


def _build_manager(base_path: Path) -> DownloadManager:
    base_path.mkdir(parents=True, exist_ok=True)
    manager = DownloadManager.__new__(DownloadManager)
    manager.socket_manager = SocketManager()
    manager.lock = threading.RLock()
    manager.jobs = {}
    manager.core_manager = CoreManager()
    manager.playlist_entry_store = PlaylistEntryStore(base_path / "playlist_entries")
    manager.job_options_store = JobOptionsStore(base_path / "job_options")
    manager.job_log_store = JobLogStore(base_path / "job_logs")
    manager.state_store = DownloadStateStore(base_path / "download_state.json")
    return manager


def _auto_remove(manager: DownloadManager, job: DownloadJob) -> bool:
    method = cast(
        Callable[[DownloadJob], bool],
        getattr(manager, "_should_auto_remove_cancelled_job"),
    )
    return method(job)


def _finalize_job(
    manager: DownloadManager,
    job_id: str,
    *,
    status: str,
    error: str | None,
) -> None:
    finalize = getattr(manager, "_finalize_job")
    finalize(job_id, status=status, error=error)


def _cleanup_cancelled_job(manager: DownloadManager, job: DownloadJob) -> None:
    cleaner = getattr(manager, "_cleanup_cancelled_job")
    cleaner(job)


def _make_cancelled_video_job(
    *, stage: str = DownloadStage.IDENTIFICANDO.value
) -> DownloadJob:
    job = DownloadJob(
        job_id="job-cancelled",
        urls=["https://example.com/watch"],
        options={},
    )
    job.status = JobStatus.CANCELLED.value
    job.kind = JobKind.VIDEO.value
    job.progress["stage"] = stage
    return job


def _make_completed_playlist_job(
    *, status: str = JobStatus.COMPLETED_WITH_ERRORS.value
) -> DownloadJob:
    job = DownloadJob(
        job_id="playlist-job",
        urls=["https://example.com/playlist"],
        options={"playlist": True},
    )
    job.status = status
    job.kind = JobKind.PLAYLIST.value
    job.progress["stage"] = DownloadStage.COMPLETED.value
    job.progress["status"] = status
    job.playlist_total_items = 3
    job.playlist_completed_indices.update({1, 2, 3})
    job.playlist_failed_indices.add(2)
    job.playlist_entry_errors[2] = PlaylistEntryError(
        index=2,
        entry_id="entry-2",
        message="Falla",
    )
    job.generated_files.add("/tmp/final-1.mp4")
    job.generated_files.add("/tmp/final-2.mp4")
    job.generated_files.add("/tmp/final-3.mp4")
    job.main_file = "/tmp/final-1.mp4"
    entries: list[PlaylistEntryMetadataPayload] = []
    for idx in range(1, 4):
        entries.append(
            {
                "index": idx,
                "entry_id": f"entry-{idx}",
                "title": f"Video {idx}",
            }
        )
    playlist_payload: PlaylistMetadataPayload = {"entries": entries}
    job.metadata["playlist"] = playlist_payload
    return job


def _add_generated_file(job: DownloadJob, _: Path) -> None:
    job.generated_files.add("output.mp4")


def _add_partial_file(job: DownloadJob, _: Path) -> None:
    job.partial_files.add("partial.part")


def _set_tmp_filename(job: DownloadJob, _: Path) -> None:
    job.progress["tmpfilename"] = "temp.part"


def _set_filename(job: DownloadJob, _: Path) -> None:
    job.progress["filename"] = "final.mp4"


def _set_main_file(job: DownloadJob, _: Path) -> None:
    job.main_file = "main.mp4"


def test_cancel_identifying_video_removes_job(tmp_path: Path) -> None:
    manager = _build_manager(tmp_path / "manager")
    job = DownloadJob(
        job_id="job-ident",
        urls=["https://example.com/watch"],
        options={},
    )
    job.status = JobStatus.STARTING.value
    job.kind = JobKind.VIDEO.value
    job.progress["stage"] = DownloadStage.IDENTIFICANDO.value
    manager.jobs[job.job_id] = job

    _finalize_job(
        manager,
        job.job_id,
        status=JobStatus.CANCELLED.value,
        error=None,
    )

    assert job.job_id not in manager.jobs


def test_delete_completed_job_preserves_output(tmp_path: Path) -> None:
    manager = _build_manager(tmp_path / "manager-complete")
    output_file = tmp_path / "final.txt"
    output_file.write_text("done", encoding="utf-8")

    job = DownloadJob(
        job_id="job-complete",
        urls=["https://example.com/watch"],
        options={},
    )
    job.status = JobStatus.COMPLETED.value
    job.kind = JobKind.VIDEO.value
    job.generated_files.add(str(output_file))
    job.main_file = str(output_file)
    manager.jobs[job.job_id] = job

    response = manager.delete_job(job.job_id)

    assert response["status"] == "deleted"
    assert output_file.exists()
    assert job.job_id not in manager.jobs


def test_delete_failed_job_removes_files(tmp_path: Path) -> None:
    manager = _build_manager(tmp_path / "manager-failed")
    partial_file = tmp_path / "partial.txt"
    partial_file.write_text("partial", encoding="utf-8")

    job = DownloadJob(
        job_id="job-failed",
        urls=["https://example.com/watch"],
        options={},
    )
    job.status = JobStatus.FAILED.value
    job.kind = JobKind.VIDEO.value
    job.generated_files.add(str(partial_file))
    job.partial_files.add(str(partial_file))
    job.progress["filename"] = str(partial_file)
    manager.jobs[job.job_id] = job

    manager.delete_job(job.job_id)

    assert not partial_file.exists()
    assert job.job_id not in manager.jobs


def test_should_auto_remove_cancelled_job_identifying_video(tmp_path: Path) -> None:
    manager = _build_manager(tmp_path / "manager-auto-remove")
    job = _make_cancelled_video_job()

    assert _auto_remove(manager, job)


def test_should_not_auto_remove_playlist_job(tmp_path: Path) -> None:
    manager = _build_manager(tmp_path / "manager-auto-remove")
    job = _make_cancelled_video_job()
    job.kind = JobKind.PLAYLIST.value
    job.playlist_completed_indices.add(1)

    assert not _auto_remove(manager, job)


def test_cancelled_job_cleanup_preserves_final_outputs(tmp_path: Path) -> None:
    manager = _build_manager(tmp_path / "manager-cancel-cleanup")
    partial_file = tmp_path / "partial.part"
    partial_file.write_text("partial", encoding="utf-8")
    final_file = tmp_path / "final.mp4"
    final_file.write_text("final", encoding="utf-8")

    job = _make_cancelled_video_job(stage=DownloadStage.PROGRESSING.value)
    job.partial_files.add(str(partial_file))
    job.generated_files.add(str(final_file))
    job.main_file = str(final_file)

    _cleanup_cancelled_job(manager, job)

    assert not partial_file.exists()
    assert final_file.exists()
    assert job.main_file == str(final_file)


def test_should_not_auto_remove_when_stage_not_identifying(tmp_path: Path) -> None:
    manager = _build_manager(tmp_path / "manager-auto-remove")
    job = _make_cancelled_video_job(stage=DownloadStage.PROGRESSING.value)

    assert not _auto_remove(manager, job)


@pytest.mark.parametrize(
    "mutator",
    (
        _add_generated_file,
        _add_partial_file,
        _set_tmp_filename,
        _set_filename,
        _set_main_file,
    ),
)
def test_should_not_auto_remove_when_artifacts_present(
    tmp_path: Path, mutator: Callable[[DownloadJob, Path], None]
) -> None:
    manager = _build_manager(tmp_path / "manager-auto-remove")
    job = _make_cancelled_video_job()
    mutator(job, tmp_path)

    assert not _auto_remove(manager, job)


def test_playlist_job_auto_remove_when_identifying_without_entries(
    tmp_path: Path,
) -> None:
    manager = _build_manager(tmp_path / "manager-playlist-auto-remove")
    job = _make_cancelled_video_job()
    job.kind = JobKind.PLAYLIST.value
    job.metadata["playlist"] = cast(PlaylistMetadataPayload, {})

    assert _auto_remove(manager, job)


def test_playlist_job_not_auto_remove_when_entry_count_present(tmp_path: Path) -> None:
    manager = _build_manager(tmp_path / "manager-playlist-auto-remove-blocked")
    job = _make_cancelled_video_job()
    job.kind = JobKind.PLAYLIST.value
    job.metadata["playlist"] = cast(PlaylistMetadataPayload, {"entry_count": 10})

    assert not _auto_remove(manager, job)


def test_delete_playlist_entries_by_index(tmp_path: Path) -> None:
    manager = _build_manager(tmp_path / "manager-playlist-delete-index")
    job = _make_completed_playlist_job()
    manager.jobs[job.job_id] = job

    response = manager.delete_playlist_entries(job.job_id, indices=[2])

    assert response["status"] == "entries_removed"
    assert response["removed_indices"] == [2]
    assert 2 in job.playlist_removed_indices
    assert 2 not in job.playlist_failed_indices
    assert 2 not in job.playlist_entry_errors
    assert job.status == JobStatus.COMPLETED.value


def test_delete_playlist_entries_by_entry_id(tmp_path: Path) -> None:
    manager = _build_manager(tmp_path / "manager-playlist-delete-id")
    job = _make_completed_playlist_job()
    manager.jobs[job.job_id] = job

    response = manager.delete_playlist_entries(
        job.job_id,
        entry_ids=["entry-2"],
    )

    assert response["status"] == "entries_removed"
    assert response["removed_indices"] == [2]
    assert 2 in job.playlist_removed_indices
    assert 2 not in job.playlist_failed_indices


def test_finalize_promotes_completed_with_errors_when_log_errors(
    tmp_path: Path,
) -> None:
    manager = _build_manager(tmp_path / "manager-log-errors")
    job = DownloadJob(
        job_id="job-with-error-logs",
        urls=["https://example.com/watch"],
        options={},
    )
    job.status = JobStatus.RUNNING.value
    job.kind = JobKind.VIDEO.value
    job.has_error_logs = True
    job.progress["status"] = JobStatus.RUNNING.value
    manager.jobs[job.job_id] = job

    _finalize_job(
        manager,
        job.job_id,
        status=JobStatus.COMPLETED.value,
        error=None,
    )

    assert job.status == JobStatus.COMPLETED_WITH_ERRORS.value
    assert job.progress.get("state") == JobStatus.COMPLETED_WITH_ERRORS.value


def test_serialize_job_includes_running_with_errors_hint(tmp_path: Path) -> None:
    manager = _build_manager(tmp_path / "manager-status-hint")
    job = DownloadJob(
        job_id="job-hint",
        urls=["https://example.com/watch"],
        options={},
    )
    job.status = JobStatus.RUNNING.value
    job.kind = JobKind.VIDEO.value
    job.has_error_logs = True
    manager.jobs[job.job_id] = job

    payload = manager.serialize_job(job, detail=False)

    assert payload["status_hint"] == "running_with_errors"
