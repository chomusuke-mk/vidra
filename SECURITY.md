# Security Policy

We appreciate responsible disclosures that keep Vidra safe for everyone.

## How to Report a Vulnerability

- **Do not** open a public issue for security problems.
- Email **7k9mc4urn@mozmail.com** with the subject line `Security Report`.
- Include:
  - A clear description of the vulnerability and potential impact
  - Steps to reproduce (commands, logs, screenshots)
  - Any temporary mitigations you discovered
- Please allow 7–10 business days for an initial response. If the issue is critical, mark it as `URGENT` in the subject line.

## Scope

- All code, assets, and tooling in this repository
- Official Vidra builds distributed by chomusuke.dev
- Third-party dependencies only insofar as Vidra’s integration exposes additional risk

## Guidelines

- Do not run destructive tests against production services owned by others.
- Avoid accessing user data; if unavoidable, explain what was accessed and delete it securely.
- Keep vulnerability details confidential until a fix is released or chomusuke.dev provides written approval.

Thanks for helping us maintain a modern, secure collaboration space.
