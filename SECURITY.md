# Security Policy

Mux Protocol provides invisible wallets and account abstraction on **Stellar/Soroban**.
`mux-backend` custodies Stellar keypairs on the server, signs and relays sponsored
transactions, and exposes authorized internal cron/cleanup surfaces. This document is
the source of truth for how security issues are reported and handled, and for the
production security requirements that every contributor and operator must respect.

---

## Reporting a Vulnerability

If you discover a security vulnerability in Mux Protocol, please report it responsibly
and **in private**.

**DO NOT file public GitHub issues for security vulnerabilities.** Making a finding
public before a fix ships can expose user funds, keys, or infrastructure.

Instead, email us at **security@muxprotocol.io** with:

- A description of the vulnerability and its potential impact
- Steps to reproduce (proof-of-concept if possible)
- Affected components (contracts, backend, SDK, frontend)
- Any suggested remediation

We will acknowledge receipt within 48 hours and aim to provide a resolution timeline
within 5 business days. We ask that you give us reasonable time to address the issue
before public disclosure.

### Response SLA

| Severity | Initial response | Update cadence |
| --- | --- | --- |
| **Critical** | Within 4 hours | Every 24 hours |
| **High** | Within 24 hours | Every 2 business days |
| **Medium** | Within 3 business days | Weekly |
| **Low** | Within 5 business days | Weekly |

Initial response means a human reply confirming the report was received and triaged.
Critical includes compromise of wallet encryption keys, uncontrolled custody signing,
or unauthorized access to internal privileged surfaces.

## Scope

This policy covers:

- Soroban smart contracts (`mux-contracts`)
- Backend services and APIs (`mux-backend`)
- SDKs and client libraries
- Web application

### In-scope vulnerability categories

- **Wallet Encryption & Key Management** — generation, encryption at rest, key
  versioning, rotation, and re-encryption of Stellar key material.
- **Custody & Transaction Signing** — server-side custody of private keys, signing,
  fee-bump relaying, and sponsor-account handling.
- **Internal Endpoint Access Control** — cron-triggered jobs, recovery administration,
  maintenance mode, and other privileged/internal endpoints.
- **API Key & Authentication** — JWT verification, API key lifecycle (hashing, expiry,
  revocation), user status enforcement, and rate limiting.
- **Data Integrity & Confidentiality** — idempotency, replay protection, webhook
  signature verification, and redaction of secrets from logs and responses.

## Custody & Transaction Signing

Mux Backend uses a **server-side custodial model**: Stellar private keys are generated,
encrypted with AES-256-GCM, and held exclusively on the server. Private key material
never crosses the client boundary and is never returned from any API. All signing and
transaction relaying happen server-side.

- Custody and **relayer** vulnerabilities are treated as high severity. Wallet
  encryption keys, signing secrets, and sponsor/relayer accounts are **private** and
  must never be committed, logged, or exposed in error responses.
- The server remains the source of truth for spends, recovery, and admin decisions;
  clients cannot bypass authz policy, idempotency, or the mainnet gates.
- See [docs/custody-security-model.md](docs/custody-security-model.md) for the full
  custody model (key generation, encryption envelope, rotation, fail-closed decrypt).

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
- Coverage: `test/cron-secret-guard.e2e-spec.ts` verifies missing/invalid/missing
  config behavior and that secrets never leak into error messages.

## Production Security Requirements

The following requirements are enforced at application startup and at runtime.
A violation is an incident — do not ship code that relaxes them.

- **`WALLET_ENCRYPTION_KEY`** — master key used to encrypt Stellar wallet private
  keys (AES-256-GCM). Required in all environments; the application refuses to
  start without it, refuses placeholders, and requires at least 32 characters.
  **Never log** this value or any derived key material.
- **`CRON_SECRET`** — required shared secret for internal cron triggers. Missing
  or mismatched values are rejected before any job logic runs.
- **`WEBHOOK_SIGNING_KEY`** / **`EXPORT_SIGNING_SECRET`** — required in production;
  the application fails closed at startup when they are missing or placeholders.
  Only hashes of webhook signing secrets are stored at rest.
- **Fail-Closed** — every privileged and money-path surface is deny-by-default:
  - Mainnet payments and fee-bump submissions are denied unless explicitly
    enabled (`FEATURE_MAINNET_PAYMENT_SUBMIT` / `PAYMENT_MAINNET_ENABLED`);
    see [docs/MAINNET-PAYMENT-FEATURE-FLAG.md](docs/MAINNET-PAYMENT-FEATURE-FLAG.md).
  - The testnet faucet refuses all requests on mainnet and on unresolved network
    misconfiguration (no default-allow path).
  - Custody decryption never falls back to plaintext; unknown key versions and
    tampered envelopes fail with stable `CUSTODY_*` error codes.
  - On RPC/DB/Horizon outages, writes fail closed rather than proceeding blind.
- **Deny-by-default authz** — owner/delegate/guardian/API-key/JWT authorization is
  enforced server-side on every privileged surface. Revoked delegates, expired
  credentials, and wrong roles are rejected before any side effect.

## Responsible Disclosure

We ask researchers and contributors to follow responsible disclosure:

1. Report the vulnerability **privately** to `security@muxprotocol.io` first.
2. Allow **90 days** from the date of your report before beginning public
   disclosure, so a fix (and, if needed, a coordinated deployment) can ship.
3. Do not publish exploit code, key material, or internal endpoint secrets.

We will not threaten legal action against good-faith researchers who follow this
policy and the safe harbor below.

## Safe Harbor

We consider security research conducted under this policy to be authorized. In
good faith, you may test systems within scope, provided you:

- Make a reasonable effort to avoid privacy violations, data destruction, and
  disruption of production services (including mainnet money paths).
- Do not access, exfiltrate, or store user funds or secret material
  (`WALLET_ENCRYPTION_KEY`, `CRON_SECRET`, JWTs, API keys, webhook secrets,
  private keys, or seed phrases).
- Do not publicly disclose a vulnerability before our 90-day responsible
  disclosure window has elapsed, unless we agree otherwise.

We will not pursue civil or criminal action — and will not report you to
platforms or law enforcement — for research that complies with this policy.

## Security Contacts

- **Security issues / vulnerability reports**: `security@muxprotocol.io`
- **Key-material incidents**: follow [docs/custody-security-model.md](docs/custody-security-model.md)
  and [docs/migration-recovery-runbook.md](docs/migration-recovery-runbook.md);
  rotate encryption/relayer keys immediately if exposure is suspected.
- **Webhook secret rotation**: [docs/webhook-secret-rotation-runbook.md](docs/webhook-secret-rotation-runbook.md)

## Security Best Practices for Contributors

- Never commit secrets, private keys, or credentials to the repository.
- Use environment variables or a secret manager for all sensitive configuration.
- Follow the principle of least privilege for all service accounts and API keys.
- Keep dependencies up to date and review security advisories regularly.
- All privileged surfaces are deny-by-default; new internal entrypoints must be
  authorized and rate-limited before they are exposed.
- **Never log** secrets, raw key material, JWTs, or webhook secrets; include
  correlation ids and stable error codes instead.

## Stellar Wave Contributors

If you are contributing through Stellar Wave, please review this document and
the relevant runbooks before touching money-path or mainnet-affecting code.
Changes to internal cron guards, authz, or secret handling must include tests
covering the auth negatives and be landed behind a feature flag or kill-switch
when they affect production behavior.

## Supported Versions

We provide security updates for the latest release of each component. Please
ensure you are running a supported version before reporting issues.

## Recognition

We appreciate the efforts of security researchers and contributors who help
keep Mux Protocol and its users safe. With your permission, we will acknowledge
your contribution in our security acknowledgements.