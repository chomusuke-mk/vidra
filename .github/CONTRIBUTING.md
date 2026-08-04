# Contributing to Vidra

Thank you for collaborating with **chomusuke.dev**. Vidra is open-source software distributed under the GNU GPLv3 license. This document outlines the process for managing issues, pull requests, and reviews.

## Basic Rules

- Respect the [Code of Conduct](./CODE_OF_CONDUCT.md) at all times.
- Do not publish public forks if they contain sensitive information. If your tools require a fork to open a pull request, configure it as **private** and delete it once the PR is merged or closed.
- Never commit secrets, production data, or third-party resources that do not belong to you.

## Reporting Issues

1. Search existing issues to avoid duplicates.
2. When opening a new issue, include:
   - Expected behavior vs. actual behavior.
   - Steps to reproduce it (commands, logs, screenshots).
   - Platform information (Operating System, Flutter version, Python version).
3. For security or licensing concerns, **do not open** a public issue: use the process described in [SECURITY.md](./SECURITY.md).

## Submitting Pull Requests

1. Create a feature branch locally (or a private fork if absolutely necessary).
2. Keep changes focused; separate unrelated fixes into distinct PRs.
3. Run linters and relevant tests (`flutter test`) before submitting your code.
4. Complete the PR template with:
   - Problem statement.
   - Proposed solution and its trade-offs.
   - Tests or verification steps performed.
5. Respond to review comments within 7 days. Inactive PRs may be closed.

### Formatting and Patch Style

- Follow the existing code style (standard Dart formatting for UI, Black/ruff for Python in the backend).
- Document non-obvious decisions with concise comments.
- Update documentation or configuration when the application behavior changes.

### Architecture and Documentation References

To understand how Vidra is structured, please read the following documents:

- **System Architecture:** [`docs/system-architecture.md`](../docs/system-architecture.md) – Overview of the Flutter client, integrated backend (`serious_python`), and native process management.
- **Client Flows:** [`docs/client-flows.md`](../docs/client-flows.md) – Details about the UI lifecycle, backend interactions, and the Overlay system.
- **Development and Packaging Guide:** [`docs/development-guide.md`](../docs/development-guide.md) – Operational practices, CI/CD packaging flows, troubleshooting, and testing strategies.

## License Notice for Contributors

By submitting code, documentation, or media resources, you agree to the terms outlined in the [`LICENSE`](../LICENSE) file:

- chomusuke.dev may redistribute your contribution as part of Vidra (including authorized proprietary builds).
- You retain the copyright and license your contribution under the GNU GPLv3.

Need help? Contact **<7k9mc4urn@mozmail.com>** with the subject `Contribution Support`.
