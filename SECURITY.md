# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Mux Protocol, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, email us at **security@muxprotocol.io** with:

- A description of the vulnerability and its potential impact
- Steps to reproduce (proof-of-concept if possible)
- Affected components (contracts, backend, SDK, frontend)
- Any suggested remediation

We will acknowledge receipt within 48 hours and aim to provide a resolution timeline within 5 business days. We ask that you give us reasonable time to address the issue before public disclosure.

## Scope

This policy covers:

- Soroban smart contracts (`mux-contracts`)
- Backend services and APIs (`mux-backend`)
- SDKs and client libraries
- Web application

## Internal Cron Jobs & Secret Guard

Internal, cron-triggered endpoints (cleanup workers, reconciliation jobs, and other
scheduled maintenance tasks) are **not** part of the public API surface. They are
guarded by a shared cron secret and are **deny-by-default**: if the secret is
missing, unset, or does not match, the request is rejected before any job logic
runs.

### Configuration

- `CRON_SECRET` — required shared secret used to authenticate internal cron
  triggers. Must be a high-entropy random value (e.g. 32+ bytes, base64/hex
  encoded). Never commit this value to the repository.
- The secret is supplied to the backend via environment/secret manager only.
  It must never appear in source, logs, error responses, or metrics.
- Cron callers must present the secret on every request (e.g. via the
  `x-cron-secret` header). Requests without a valid secret receive a stable
  `401`/`403` error code and are not executed.

### Rotation

1. Generate a new high-entropy secret in the secret manager.
2. Update the cron scheduler / trigger configuration to send the new value.
3. Roll the backend deployment so it reads the new `CRON_SECRET`.
4. Verify scheduled jobs still succeed and that unauthenticated requests are
   rejected.
5. Revoke the previous secret.

Rotation should be performed on a regular schedule and immediately if a secret
is suspected to be compromised. Because the guard is fail-closed, a missing or
mismatched secret disables the internal jobs rather than exposing them.

### Operational Notes

- Auth failures are logged with a correlation/request id and a stable error
  code, but **never** log the secret value or raw key material.
- Internal job endpoints are rate-limited and idempotent; replayed or
  concurrent triggers must not cause duplicate side effects.
- On dependency outages (RPC/DB/Horizon), internal write paths fail closed.

## Security Best Practices for Contributors

- Never commit secrets, private keys, or credentials to the repository.
- Use environment variables or a secret manager for all sensitive configuration.
- Follow the principle of least privilege for all service accounts and API keys.
- Keep dependencies up to date and review security advisories regularly.
- All privileged surfaces are deny-by-default; new internal entrypoints must be
authorized and rate-limited before they are exposed.

## Verification Scripts (CI Gates)

The repository ships fail-closed verification scripts that assert the documented
security invariants for custody, wallet orchestration, and idempotent user
creation. They run as the `verify-scripts` CI job and exit non-zero on any
violation; a failing script blocks merge:

- `verify-encryption.sh` — key encryption at rest, controlled decryption, safe
  decryption-failure handling, strong cipher, boot-time key validation.
- `verify-orchestrator.sh` — atomic/idempotent wallet creation, one wallet per
  user, fail-closed dependency outages, authz, feature-flag gating.
- `verify-idempotent-user.sh` — `findOrCreateUser`, `authId` uniqueness,
  existing-user return, authz gating, schema invariants.
- `scripts/verify-key-management-consolidation.sh` — key-management
  consolidation invariants.

The scripts never print raw key material, JWTs, or webhook secrets. If an
invariant changes, update the script **and** its cited reference document in the
same PR (see README § Verification Scripts and `docs/custody-security-model.md`).
Do not bypass these gates with `continue-on-error`.

## Stellar Wave Contributors

If you are contributing through Stellar Wave, please review this document and
the relevant runbooks before touching money-path or mainnet-affecting code.
Changes to internal cron guards, authz, or secret handling must include tests
covering the auth negatives and be landed behind a feature flag or kill-switch
when they affect production behavior.

### Custody Key Management Verification

The codebase includes a fail-closed static verification gate for the custody-key
management consolidation invariants:

- **Script**: `scripts/verify-key-management-consolidation.ts` &
  `scripts/verify-key-management-consolidation.sh`
- **Run**: `pnpm verify:key-consolidation` (required CI check)
- **Docs verified against**:
  - [Custody Security Model](docs/custody-security-model.md)
  - [Key Management Consolidation](docs/key-management-consolidation.md)
  - [Mainnet Payment Feature Flag](docs/MAINNET-PAYMENT-FEATURE-FLAG.md)
  - [Key Management Migration Guide](docs/MIGRATION-KEY-MANAGEMENT.md)

Invariants checked: no direct key generation in money-path services, no committed
private key material, envelope-at-rest schema fields, deny-by-default authz,
correlation ids, stable error codes, fail-closed dependency handling, response
redaction, and mainnet pay-path kill-switch defaults.

The gate always runs offline (no database or RPC required), uses stable exit codes
(0=pass, 1=findings, 2/3=infra/misuse), and rejects any environment override that
would disable it (deny-by-default). Findings report `file:line` locations without
raw key material — secrets are never echoed in output.

## Supported Versions

We provide security updates for the latest release of each component. Please
ensure you are running a supported version before reporting issues.

## Recognition

We appreciate the efforts of security researchers and contributors who help
keep Mux Protocol and its users safe. With your permission, we will acknowledge
your contribution in our security acknowledgements.
