# Security Policy

## Scope

WireStub is a test harness, but HAR files and diagnostics can still contain sensitive data. Treat fixtures and test artifacts as potentially secret-bearing inputs.

## HAR secret handling

- **Never commit raw third-party HAR files without review.**
- Run `wirestub validate` before committing fixtures.
- Prefer `wirestub sanitize` before sharing or checking in HAR files.
- Remember that sanitized HAR files may still contain sensitive-looking **field names** such as `access_token` or `password`, even though the **values** are redacted.
- WireStub redacts rendered diagnostics and CLI output, but it cannot protect source HAR files you have not sanitized.

## Reporting a vulnerability

If you discover a security issue, especially around secret leakage in diagnostics, sanitizer behavior, or transport isolation, please open a private security advisory or contact the maintainer directly before publishing details.

## Non-goals

WireStub does not attempt to provide:

- HTTPS interception / MITM
- physical-device network interception
- production traffic proxying
- credential storage or secret management
