from typing import Dict, List, NotRequired, TypedDict

from ...models.api.websockets import OverviewSummary
from ...models.download.manager import SerializedJobPayload
from ...models.shared import JSONValue


DryRunOptionsPayload = Dict[str, JSONValue]


class HealthCheckResponse(TypedDict):
    service: str
    time: str
    overview: OverviewSummary
    description: NotRequired[str]
    metadata: NotRequired[Dict[str, JSONValue]]
    base_url: NotRequired[str]
    api_url: NotRequired[str]
    overview_socket_url: NotRequired[str]
    job_socket_base_url: NotRequired[str]
    timeout_seconds: NotRequired[int]


class CreateJobEndpointResponse(TypedDict):
    job_id: str
    status: str
    created_at: str
    stage: NotRequired[str]
    stage_name: NotRequired[str]
    stage_status: NotRequired[str]
    stage_percent: NotRequired[float]
    percent: NotRequired[float]
    message: NotRequired[str]


class ListJobsEndPointResponse(TypedDict):
    jobs: List[SerializedJobPayload]
    summary: OverviewSummary


class DryRunJobEndPointResponse(TypedDict):
    cli_args: List[str]
    urls: List[str]
    options: DryRunOptionsPayload
