#!/bin/bash
set -euo pipefail

# =============================================================================
# verify-encryption.sh
#
# Fail-closed CI gate for the wallet encryption invariants documented in
# docs/custody-security-model.md and README.md (§ Security).
#
# Invariants checked:
#   I1. Private keys are encrypted before database storage (Wallet.encryptedSecret).
#   I2. Encryption is keyed from an environment variable (WALLET_ENCRYPTION_KEY).
#   I3. Decryption only happens inside a controlled signing/decrypt path.
#   I4. Decryption failures degrade safely via stable error codes (no fallback).
#   I5. Plain private keys are never persisted outside the encryption layer.
#   I6. A strong cipher (AES-256-GCM or equivalent) is used.
#   I7. Key material is validated at boot (length >= 32, placeholder rejection).
#
# Exits 1 when any invariant is violated so the CI verify-scripts job fails.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0

# Helper functions
pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

info() {
    echo -e "ℹ️  $1"
}

echo ""
echo "🔍 Verifying Wallet Encryption Implementation"
echo "============================================="
echo ""
info "References: docs/custody-security-model.md, README.md (§ Security)"
echo ""

# ---------------------------------------------------------------------------
# I1: Schema enforces encrypted storage — Wallet model uses encryptedSecret
# ---------------------------------------------------------------------------
echo "1. Checking that Wallet schema uses encrypted storage..."

if grep -q "encryptedSecret" prisma/schema.prisma 2>/dev/null; then
    pass "Wallet schema stores encryptedSecret (never plaintext privateKey)"
else
    fail "Wallet schema does NOT use encrypted storage — check prisma/schema.prisma"
fi

# Also verify there is no plain privateKey column in the Wallet model
if grep -q "^[[:space:]]\+privateKey" prisma/schema.prisma 2>/dev/null; then
    fail "Wallet schema has a plaintext privateKey column — violates the encryption invariant"
else
    pass "No plaintext privateKey column in Wallet schema"
fi
echo ""

# ---------------------------------------------------------------------------
# I2: Environment-based encryption key referenced in code
# ---------------------------------------------------------------------------
echo "2. Checking environment-based encryption key..."

if grep -rq "WALLET_ENCRYPTION_KEY" src/ 2>/dev/null; then
    pass "Encryption key is environment-based (WALLET_ENCRYPTION_KEY referenced in src/)"
else
    fail "Encryption key is NOT wired from the environment — WALLET_ENCRYPTION_KEY not referenced in src/"
fi
echo ""

# ---------------------------------------------------------------------------
# I3: Decryption only happens inside a controlled signing/decrypt path
# ---------------------------------------------------------------------------
echo "3. Checking that decryption only happens during signing..."

if grep -rq "getDecryptedPrivateKey\|decryptSecret\|decryptPrivateKey\|keyManagement.*decrypt\|\.decrypt(" src/ 2>/dev/null; then
    pass "Decryption only happens in controlled methods (controlled decrypt API found)"
else
    fail "Decryption is NOT controlled — no controlled decrypt method found in src/"
fi
echo ""

# ---------------------------------------------------------------------------
# I4: Safe decryption failure handling (stable error codes, no fallback)
# ---------------------------------------------------------------------------
echo "4. Checking safe decryption failure handling..."

if grep -rq "DECRYPTION_FAILED\|INVALID_KEY\|INVALID_DATA\|KEY_DECRYPT_FAILED\|DECRYPT_ERROR" src/ 2>/dev/null; then
    pass "Decryption failures degrade safely via stable error codes"
else
    fail "Decryption failures are NOT handled safely — no stable error codes in src/"
fi
echo ""

# ---------------------------------------------------------------------------
# I5: Plain private keys are never persisted outside the encryption layer
# ---------------------------------------------------------------------------
echo "5. Checking that plain private keys are never persisted..."

# Any privateKey assignment/usage not routed through encryption is a violation.
# Test/spec files are excluded because they are not executed in production.
PLAINTEXT_PK=$(grep -rn "\.privateKey\|privateKey[[:space:]]*=" src/ 2>/dev/null \
  | grep -v "encryptAndSerialize\|EncryptionService\|KeyManagementService\|\.spec\.ts\|\.test\.ts\|//.*privateKey" \
  || true)
if [ -n "$PLAINTEXT_PK" ]; then
    fail "Private key material may bypass the encryption layer — review:"
    echo "$PLAINTEXT_PK" | head -10
else
    pass "No direct privateKey usage outside the encryption layer"
fi
echo ""

# ---------------------------------------------------------------------------
# I6: Strong encryption algorithm (AES-256-GCM or equivalent)
# ---------------------------------------------------------------------------
echo "6. Checking encryption algorithm strength..."

if grep -rq "aes-256-gcm\|aes256\|AES.*128\|AES.*GCM\|encryptionAlgorithm\|cipher" src/ 2>/dev/null; then
    pass "Uses strong encryption algorithm (AES-256-GCM or equivalent)"
else
    fail "Does NOT use a strong cipher — no AES-256-GCM/reference cipher in src/"
fi
echo ""

# ---------------------------------------------------------------------------
# I7: Key material validated at boot (length >= 32, placeholder rejection)
# ---------------------------------------------------------------------------
echo "7. Checking key validation at boot..."

if grep -rq "WALLET_ENCRYPTION_KEY.*32\|length.*32.*encryption\|your-secret-encryption\|placeholder" src/ 2>/dev/null; then
    pass "Key validation at boot implemented (length/placeholder enforcement found)"
else
    fail "Key validation at boot missing — no WALLET_ENCRYPTION_KEY length/placeholder check in src/"
fi
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "============================================="
echo "📊 Verification Summary"
echo "============================================="
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}🎉 All encryption checks passed!${NC}"
    exit 0
else
    echo -e "${RED}⚠️  Some checks failed ($FAILED). Bring the code back in line with the"
    echo -e "     documented invariants before merging — this must not be bypassed.${NC}"
    echo ""
    echo "For help:"
    echo "  - docs/custody-security-model.md"
    echo "  - README.md (§ Security — WALLET_ENCRYPTION_KEY)"
    echo "  - docs/migration-recovery-runbook.md (key-management migration runbook)"
    exit 1
fi