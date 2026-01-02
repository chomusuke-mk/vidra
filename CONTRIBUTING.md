# Contributing to Vidra

Thanks for collaborating with **chomusuke.dev**. Vidra is source-available under the VSACL, which means contributions are welcome but redistribution is restricted. This document outlines the process for issues, pull requests, and review.

## Ground Rules
- Follow the [Code of Conduct](./CODE_OF_CONDUCT.md) at all times.
- Do not publish public forks. If your tooling requires a fork to open a pull request, set it to **private** and delete it once the PR is merged or closed.
- Never commit secrets, production data, or vendor assets you do not own.

## Reporting Issues
1. Search existing issues to avoid duplicates.
2. When filing a new issue, include:
	- Expected vs. actual behavior
	- Steps to reproduce (commands, logs, screenshots)
	- Platform information (OS, Flutter version, Python version)
3. For security or licensing concerns **do not** open a public issue—use the process in [SECURITY.md](./SECURITY.md) instead.

## Submitting Pull Requests
1. Create a feature branch locally (or a private fork if absolutely necessary).
2. Keep changes focused; separate unrelated fixes into distinct PRs.
3. Run relevant linters/tests (`flutter test`, `pytest`, etc.) before submitting.
4. Fill out the PR template with:
	- Problem statement
	- Proposed solution & trade-offs
	- Tests or verification steps performed
5. Respond to review feedback within 7 days. PRs that go stale may be closed.

### Patch Format & Style
- Follow the existing code style (Dart format, Black/ruff for Python).
- Document non-obvious decisions with concise comments.
- Update docs or configuration when behavior changes.

### Architecture & docs references
- Backend architecture, typed models, and job lifecycle: [`docs/system-architecture.md`](docs/system-architecture.md), [`docs/typed-architecture.md`](docs/typed-architecture.md), [`docs/backend-job-lifecycle.md`](docs/backend-job-lifecycle.md).
- Client/UI flows and implementation details: [`docs/client-flows.md`](docs/client-flows.md), [`docs/client-architecture.md`](docs/client-architecture.md).
- Ops + release playbooks: [`docs/configuration-and-ops.md`](docs/configuration-and-ops.md), [`docs/packaging-and-release.md`](docs/packaging-and-release.md), [`docs/troubleshooting.md`](docs/troubleshooting.md), [`docs/testing-strategy.md`](docs/testing-strategy.md).

## Contributor License Notice
By submitting code, docs, or media you agree to the terms in [`LICENSE`](./LICENSE):
- chomusuke.dev may redistribute your contribution as part of Vidra (including proprietary builds).
- You retain copyright but grant an irrevocable license compatible with VSACL.

Need help? Contact **7k9mc4urn@mozmail.com** with the subject line `Contribution Support`.
