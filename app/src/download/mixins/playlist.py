from __future__ import annotations

import copy
from typing import List, Mapping, Optional, Sequence, Set, cast

from ...config.constants import ApiRoute, JobStatus
from ...download.mixins.manager_utils import (
    ManagerUtilsMixin,
    metadata_get_playlist_model,
    metadata_store_playlist_model,
)
from ...download.mixins.protocols import PlaylistManagerProtocol
from ...download.models import (
    DownloadJob,
    DownloadJobMetadataPayload,
    DownloadJobProgressPayload,
)
from ...models.download.mixins.preview import PlaylistSnapshotPayload
from ...models.download.playlist_entry_error import PlaylistEntryErrorPayload
from ...utils import to_float, to_int
from ...models.shared import (
    PlaylistEntryMetadata,
    PlaylistEntryMetadataPayload,
    PlaylistEntryProgressSnapshot,
    PlaylistEntryReference,
    PlaylistMetadata,
    PreviewMetadata,
)


class PlaylistMixin(ManagerUtilsMixin):
    def _playlist_manager(self) -> "PlaylistManagerProtocol":
        return cast("PlaylistManagerProtocol", self)

    def build_playlist_snapshot(
        self,
        job_id: str,
        *,
        include_entries: bool = False,
        include_entry_progress: bool = False,
        entry_offset: Optional[int] = None,
        max_entries: Optional[int] = None,
    ) -> Optional[PlaylistSnapshotPayload]:
        manager = self._playlist_manager()
        with manager.lock:
            job = manager.jobs.get(job_id)
            if not job:
                return None
            snapshot = self._compose_playlist_snapshot(
                job,
                include_entries=include_entries,
                include_entry_progress=include_entry_progress,
                entry_offset=entry_offset,
                max_entries=max_entries,
            )
        return snapshot

    def build_playlist_entries(
        self,
        job_id: str,
        *,
        entry_offset: Optional[int] = None,
        max_entries: Optional[int] = None,
    ) -> Optional[PlaylistSnapshotPayload]:
        return self.build_playlist_snapshot(
            job_id,
            include_entries=True,
            include_entry_progress=True,
            entry_offset=entry_offset,
            max_entries=max_entries,
        )

    def _compose_playlist_snapshot(
        self,
        job: DownloadJob,
        *,
        include_entries: bool = False,
        include_entry_progress: bool = False,
        entry_offset: Optional[int] = None,
        max_entries: Optional[int] = None,
    ) -> Optional[PlaylistSnapshotPayload]:
        metadata: DownloadJobMetadataPayload = job.metadata or {}
        playlist_model = metadata_get_playlist_model(metadata, clone=True)
        if playlist_model is None:
            playlist_meta_raw = metadata.get("playlist")
            if not isinstance(playlist_meta_raw, dict):
                return None
            playlist_model_actual = PlaylistMetadata.from_payload(playlist_meta_raw)
            metadata_store_playlist_model(metadata, playlist_model_actual)
            playlist_model = copy.deepcopy(playlist_model_actual)

        selected_indices = self._resolve_selected_playlist_indices(job)

        progress_state: DownloadJobProgressPayload = cast(
            DownloadJobProgressPayload,
            dict(job.progress) if job.progress else {},
        )
        completed_indices = {
            index_value
            for index_value in (
                to_int(index) for index in job.playlist_completed_indices
            )
            if index_value is not None
        }
        if selected_indices:
            completed_indices.intersection_update(selected_indices)

        failed_indices = {
            index_value
            for index_value in (to_int(index) for index in job.playlist_failed_indices)
            if index_value is not None
        }
        if selected_indices:
            failed_indices.intersection_update(selected_indices)

        error_indices = {
            index_value
            for index_value in (
                to_int(getattr(record, "index", None))
                for record in job.playlist_entry_errors.values()
            )
            if index_value is not None
        }
        if selected_indices and error_indices:
            error_indices.intersection_update(selected_indices)
        if error_indices:
            failed_indices.update(error_indices)

        pending_retry_indices = {
            index_value
            for index_value in (to_int(index) for index in job.playlist_pending_indices)
            if index_value is not None
        }
        if selected_indices:
            pending_retry_indices.intersection_update(selected_indices)
        removed_indices = {
            index_value
            for index_value in (to_int(index) for index in job.playlist_removed_indices)
            if index_value is not None
        }
        if selected_indices:
            removed_indices.intersection_update(selected_indices)

        if removed_indices:
            completed_indices.difference_update(removed_indices)
            failed_indices.difference_update(removed_indices)
            pending_retry_indices.difference_update(removed_indices)
        current_index = to_int(
            progress_state.get("playlist_index")
            or progress_state.get("playlist_current_index")
        )
        if selected_indices and (current_index not in selected_indices):
            current_index = None

        base_entries: Sequence[PlaylistEntryMetadata] = playlist_model.entries or []
        sanitized_entries: List[PlaylistEntryMetadata] = []
        entry_refs: List[PlaylistEntryReference] = []
        for entry_model in base_entries:
            if entry_model.index <= 0:
                continue
            if selected_indices and entry_model.index not in selected_indices:
                continue
            enriched = self._enrich_playlist_entry_metadata(
                entry_model,
                completed_indices,
                failed_indices,
                removed_indices,
                current_index,
            )
            if not enriched:
                continue
            sanitized_entries.append(enriched)
            ref = PlaylistEntryReference(
                index=enriched.index,
                entry_id=enriched.entry_id,
                status=enriched.status,
            )
            entry_refs.append(ref)

        total_items = job.playlist_total_items
        if selected_indices:
            total_items = len(selected_indices)
        metadata_total = playlist_model.entry_count
        if total_items is None or total_items <= 0:
            if metadata_total is not None and metadata_total > 0:
                total_items = metadata_total
            elif sanitized_entries:
                total_items = len(sanitized_entries)
        pending_items: Optional[int] = None
        percent_complete: Optional[float] = None
        effective_total: Optional[int] = total_items
        if effective_total is not None:
            effective_total = max(effective_total - len(removed_indices), 0)
            if effective_total == 0:
                pending_items = 0
                percent_complete = 100.0
            else:
                pending_items = max(effective_total - len(completed_indices), 0)
                percent_complete = round(
                    (len(completed_indices) / effective_total) * 100,
                    2,
                )

        playlist_model.entries_endpoint = ApiRoute.JOB_PLAYLIST_ITEMS.value.format(
            job_id=job.job_id
        )
        playlist_model.entry_refs = entry_refs
        if selected_indices:
            playlist_model.selected_indices = [
                int(index) for index in sorted(selected_indices)
            ]
        else:
            playlist_model.selected_indices = []

        if effective_total is not None:
            playlist_model.entry_count = effective_total
            playlist_model.total_items = effective_total
        elif metadata_total is not None and metadata_total > 0:
            playlist_model.entry_count = metadata_total

        playlist_model.completed_items = len(completed_indices)
        playlist_model.pending_items = pending_items
        playlist_model.percent = percent_complete
        if current_index is not None and current_index > 0:
            playlist_model.current_index = current_index
        current_entry_id = self._resolve_playlist_entry_id_from_entries(
            sanitized_entries,
            current_index,
        )
        if current_entry_id:
            playlist_model.current_entry_id = current_entry_id

        if playlist_model.thumbnails:
            best_thumbnail = self._select_best_thumbnail_url(
                [thumb.to_payload() for thumb in playlist_model.thumbnails]
            )
            if best_thumbnail and not playlist_model.thumbnail_url:
                playlist_model.thumbnail_url = best_thumbnail

        playlist_model.entries = sanitized_entries
        entries_version = getattr(job, "playlist_entries_version", None)
        if isinstance(entries_version, int) and entries_version > 0:
            playlist_model.entries_version = entries_version
            playlist_model.entries_external = True

        if include_entries and include_entry_progress:
            for entry_model in sanitized_entries:
                self._populate_entry_progress_snapshot(
                    job,
                    entry_model,
                    progress_state,
                    current_index=current_index,
                    completed_indices=completed_indices,
                )

        playlist_payload = playlist_model.to_payload(include_entries=False)
        completed_index_list = [int(index) for index in sorted(completed_indices)]
        if completed_index_list:
            playlist_payload["completed_indices"] = completed_index_list

        if failed_indices:
            playlist_payload["failed_indices"] = [
                int(index) for index in sorted(failed_indices)
            ]

        if pending_retry_indices:
            playlist_payload["pending_retry_indices"] = [
                int(index) for index in sorted(pending_retry_indices)
            ]

        if removed_indices:
            playlist_payload["removed_indices"] = [
                int(index) for index in sorted(removed_indices)
            ]

        if job.playlist_entry_errors:
            entry_errors_payload: List[PlaylistEntryErrorPayload] = []
            for index, record in sorted(job.playlist_entry_errors.items()):
                if index <= 0:
                    continue
                if selected_indices and index not in selected_indices:
                    continue
                payload_dict = record.to_json()
                if index in pending_retry_indices:
                    updated_payload = dict(payload_dict)
                    updated_payload["pending_retry"] = True
                    payload_dict = cast(
                        PlaylistEntryErrorPayload,
                        updated_payload,
                    )
                entry_errors_payload.append(payload_dict)
            if entry_errors_payload:
                playlist_payload["entry_errors"] = entry_errors_payload

        slice_offset = entry_offset if isinstance(entry_offset, int) else 0
        if slice_offset < 0:
            slice_offset = 0
        slice_limit = max_entries if isinstance(max_entries, int) else None
        if slice_limit is not None and slice_limit <= 0:
            slice_limit = None
        slice_end = slice_offset + slice_limit if slice_limit is not None else None
        include_slice = include_entries
        sliced_entries = sanitized_entries
        slice_applied = False
        if include_slice and (slice_offset > 0 or slice_end is not None):
            sliced_entries = sanitized_entries[slice_offset:slice_end]
            slice_applied = len(sliced_entries) != len(sanitized_entries)
        if not include_entries or slice_applied:
            playlist_model.entries_external = True

        if include_entries:
            entries_payload: List[PlaylistEntryMetadataPayload] = [
                entry.to_payload() for entry in sliced_entries
            ]
            playlist_payload["entries"] = entries_payload
            if slice_offset > 0:
                playlist_payload["entries_offset"] = slice_offset
            if slice_applied and slice_end is not None:
                playlist_payload["entries_truncated"] = True
                playlist_payload["entries_external"] = True

        snapshot: PlaylistSnapshotPayload = {
            "job_id": job.job_id,
            "status": job.status,
            "playlist": playlist_payload,
        }
        return snapshot

    def _resolve_playlist_entry_id_from_entries(
        self,
        entries: Sequence[PlaylistEntryMetadata],
        index: Optional[int],
    ) -> Optional[str]:
        if index is None or index <= 0:
            return None
        for entry in entries:
            if entry.index == index:
                if entry.entry_id and entry.entry_id.strip():
                    return entry.entry_id.strip()
                if entry.webpage_url and entry.webpage_url.strip():
                    return entry.webpage_url.strip()
                return None
        return None

    def _resolve_playlist_index_from_entry_id(
        self,
        job: DownloadJob,
        entry_id: Optional[str],
    ) -> Optional[int]:
        if not entry_id:
            return None
        normalized_id = entry_id.strip()
        if not normalized_id:
            return None
        metadata: DownloadJobMetadataPayload = job.metadata or {}
        playlist_model = metadata_get_playlist_model(metadata, clone=True)
        if playlist_model is None:
            playlist_meta_raw = metadata.get("playlist")
            if not isinstance(playlist_meta_raw, dict):
                return None
            playlist_model = PlaylistMetadata.from_payload(playlist_meta_raw)
        for raw_entry in playlist_model.entries:
            candidate_id = raw_entry.entry_id or raw_entry.webpage_url
            if isinstance(candidate_id, str) and candidate_id.strip() == normalized_id:
                index_value = raw_entry.index
                if index_value > 0:
                    return index_value
                return None
        return None

    def _resolve_playlist_entry_id(
        self,
        job: DownloadJob,
        index: Optional[int],
    ) -> Optional[str]:
        if index is None or index <= 0:
            return None
        metadata: DownloadJobMetadataPayload = job.metadata or {}
        playlist_model = metadata_get_playlist_model(metadata, clone=True)
        if playlist_model is None:
            playlist_meta_raw = metadata.get("playlist")
            if not isinstance(playlist_meta_raw, dict):
                return None
            playlist_model = PlaylistMetadata.from_payload(playlist_meta_raw)
        for entry in playlist_model.entries:
            if entry.index == index:
                if entry.entry_id and entry.entry_id.strip():
                    return entry.entry_id.strip()
                if entry.webpage_url and entry.webpage_url.strip():
                    return entry.webpage_url.strip()
                return None
        return None

    def resolve_playlist_entry_id(
        self,
        job: DownloadJob,
        index: Optional[int],
    ) -> Optional[str]:
        return self._resolve_playlist_entry_id(job, index)

    def resolve_playlist_index_from_entry_id(
        self,
        job: DownloadJob,
        entry_id: Optional[str],
    ) -> Optional[int]:
        return self._resolve_playlist_index_from_entry_id(job, entry_id)

    def _populate_entry_progress_snapshot(
        self,
        job: DownloadJob,
        entry: PlaylistEntryMetadata,
        job_progress: DownloadJobProgressPayload,
        *,
        current_index: Optional[int],
        completed_indices: Set[int],
    ) -> None:
        entry_index = entry.index
        if entry_index <= 0:
            entry.progress_snapshot = None
            entry.is_current = False
            entry.is_completed = False
            return

        snapshot = PlaylistEntryProgressSnapshot()
        stored_snapshot = entry.progress_snapshot

        def _int_value(key: str) -> Optional[int]:
            return to_int(job_progress.get(key))

        def _float_value(key: str, *, precision: int = 3) -> Optional[float]:
            numeric = to_float(job_progress.get(key))
            if numeric is None:
                return None
            return round(numeric, precision)

        def _string_value(key: str) -> Optional[str]:
            raw_value = job_progress.get(key)
            if raw_value is None:
                return None
            if isinstance(raw_value, str):
                text = raw_value.strip()
            else:
                text = str(raw_value).strip()
            return text or None

        def _percent_value(key: str) -> Optional[float]:
            numeric = to_float(job_progress.get(key))
            if numeric is None:
                return None
            return round(numeric, 2)

        entry_status = entry.status or None
        is_current = False
        is_completed = bool(entry.is_completed)

        is_active_entry = current_index is not None and entry_index == current_index
        in_completed_set = entry_index in completed_indices

        if is_active_entry:
            snapshot.status = (
                _string_value("status") or job.status or JobStatus.RUNNING.value
            )
            percent_value = _percent_value("percent")
            stage_percent_value = _percent_value("stage_percent")
            if percent_value is None and stage_percent_value is not None:
                percent_value = stage_percent_value
            if stage_percent_value is None and percent_value is not None:
                stage_percent_value = percent_value
            snapshot.percent = percent_value
            snapshot.stage_percent = stage_percent_value
            snapshot.stage = _string_value("stage") or "downloading"
            snapshot.stage_name = _string_value("stage_name") or snapshot.stage
            snapshot.downloaded_bytes = _int_value("downloaded_bytes") or 0
            snapshot.total_bytes = _int_value("total_bytes")
            snapshot.speed = _float_value("speed")
            snapshot.eta = _int_value("eta")
            snapshot.elapsed = _float_value("elapsed")
            snapshot.message = _string_value("message")
            entry_status = snapshot.status or JobStatus.RUNNING.value
            is_current = True
            is_completed = False
        elif in_completed_set:
            snapshot.status = JobStatus.COMPLETED.value
            snapshot.percent = 100.0
            snapshot.stage_percent = 100.0
            snapshot.stage = "completed"
            snapshot.stage_name = "completed"
            entry_status = JobStatus.COMPLETED.value
            is_current = False
            is_completed = True
        else:
            default_status = JobStatus.QUEUED.value
            if job.status in {JobStatus.FAILED.value, JobStatus.CANCELLED.value}:
                default_status = job.status
            snapshot.status = default_status
            snapshot.percent = 0.0
            snapshot.stage_percent = 0.0
            snapshot.stage = "queued"
            snapshot.stage_name = "queued"
            snapshot.downloaded_bytes = 0
            entry_status = default_status
            is_current = False
            is_completed = False

        if stored_snapshot:
            for attr in (
                "downloaded_bytes",
                "total_bytes",
                "speed",
                "eta",
                "elapsed",
                "percent",
                "stage_percent",
                "status",
                "stage",
                "stage_name",
                "message",
                "state",
                "timestamp",
            ):
                value = getattr(stored_snapshot, attr)
                if value is not None:
                    setattr(snapshot, attr, value)

        snapshot_state = (snapshot.state or "").strip().lower()
        if snapshot_state == JobStatus.COMPLETED.value:
            entry_status = snapshot.status or JobStatus.COMPLETED.value
            is_current = False
            is_completed = True
        elif snapshot_state == "active":
            entry_status = snapshot.status or JobStatus.RUNNING.value
            is_current = True
            is_completed = False
        elif snapshot_state in {
            JobStatus.FAILED.value,
            JobStatus.CANCELLED.value,
        }:
            entry_status = snapshot.status or snapshot_state
            is_current = False
            is_completed = False

        if snapshot.has_data():
            entry.progress_snapshot = snapshot
        else:
            entry.progress_snapshot = None

        entry.status = entry_status or entry.status or JobStatus.QUEUED.value
        entry.is_current = is_current
        entry.is_completed = is_completed

    def _enrich_playlist_entry_metadata(
        self,
        entry: PlaylistEntryMetadata,
        completed_indices: Set[int],
        failed_indices: Set[int],
        removed_indices: Set[int],
        current_index: Optional[int],
    ) -> Optional[PlaylistEntryMetadata]:
        if entry.index <= 0:
            return None

        entry_id_value = entry.entry_id or entry.webpage_url
        if entry_id_value:
            entry.entry_id = entry_id_value.strip()

        preview = entry.preview or PreviewMetadata()
        if entry.entry_id and not preview.entry_id:
            preview.entry_id = entry.entry_id
        if entry.title and not preview.title:
            preview.title = entry.title
        if entry.uploader and not preview.uploader:
            preview.uploader = entry.uploader
        if entry.uploader_url and not preview.uploader_url:
            preview.uploader_url = entry.uploader_url
        if entry.channel and not preview.channel:
            preview.channel = entry.channel
        if entry.channel_url and not preview.channel_url:
            preview.channel_url = entry.channel_url
        if entry.webpage_url:
            preview.webpage_url = entry.webpage_url
            if not preview.original_url:
                preview.original_url = entry.webpage_url
        if entry.duration_seconds is not None and preview.duration_seconds is None:
            preview.duration_seconds = entry.duration_seconds
        if entry.duration_text and not preview.duration_text:
            preview.duration_text = entry.duration_text
        if entry.view_count is not None and preview.view_count is None:
            preview.view_count = entry.view_count

        if entry.thumbnails and not preview.thumbnails:
            preview.thumbnails = list(entry.thumbnails)

        if entry.thumbnail_url and not preview.thumbnail_url:
            preview.thumbnail_url = entry.thumbnail_url
        elif entry.thumbnails:
            best_thumb = self._select_best_thumbnail_url(
                [thumb.to_payload() for thumb in entry.thumbnails]
            )
            if best_thumb and not preview.thumbnail_url:
                preview.thumbnail_url = best_thumb

        if preview.has_data():
            entry.preview = preview
        else:
            entry.preview = None

        if entry.index in removed_indices:
            status = "removed"
        elif entry.index in completed_indices:
            status = (
                JobStatus.COMPLETED_WITH_ERRORS.value
                if entry.index in failed_indices
                else JobStatus.COMPLETED.value
            )
        elif entry.index in failed_indices:
            status = JobStatus.FAILED.value
        elif current_index is not None and entry.index == current_index:
            status = "active"
        else:
            status = "pending"
        entry.status = status
        entry.is_completed = status in {
            JobStatus.COMPLETED.value,
            JobStatus.COMPLETED_WITH_ERRORS.value,
        }
        entry.is_current = (
            current_index is not None
            and entry.index == current_index
            and status != "removed"
        )

        return entry

    def _resolve_selected_playlist_indices(self, job: DownloadJob) -> Set[int]:
        selected: Set[int] = set()
        playlist_config_raw = cast(object, job.options.get("playlist"))
        playlist_items_raw: object = job.options.get("playlist_items")
        if isinstance(playlist_config_raw, Mapping):
            playlist_mapping = cast(Mapping[str, object], playlist_config_raw)
            playlist_items_raw = playlist_mapping.get("items")
        parts = self._normalize_playlist_items_spec(playlist_items_raw)
        if not parts:
            return selected
        for part in parts:
            if "-" in part:
                start_str, end_str = part.split("-", 1)
                start_index = to_int(start_str)
                end_index = to_int(end_str)
                if start_index is None or end_index is None:
                    continue
                for value in range(start_index, end_index + 1):
                    if value > 0:
                        selected.add(value)
            else:
                index_value = to_int(part)
                if index_value is not None and index_value > 0:
                    selected.add(index_value)
        return selected

    @staticmethod
    def _normalize_playlist_items_spec(value: object) -> List[str]:
        if value is None:
            return []
        if isinstance(value, str):
            return [
                segment
                for segment in (part.strip() for part in value.split(","))
                if segment
            ]
        if isinstance(value, Sequence) and not isinstance(
            value, (str, bytes, bytearray)
        ):
            normalized: List[str] = []
            sequence_value = cast(Sequence[object], value)
            for item in sequence_value:
                if item is None:
                    continue
                text = str(item).strip()
                if text:
                    normalized.append(text)
            return normalized
        text = str(value).strip()
        return [text] if text else []
