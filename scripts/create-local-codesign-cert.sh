#!/bin/bash
# Create a stable local code signing certificate for PasteDeck development builds.
#
# Run once before scripts/build-dmg.sh. The DMG build will reuse this identity so
# macOS Accessibility (TCC) can keep recognizing the app across rebuilds.

set -euo pipefail

IDENTITY_NAME="${CODE_SIGN_IDENTITY:-PasteDeck Local Code Signing}"
KEYCHAIN="${KEYCHAIN_PATH:-${HOME}/Library/Keychains/login.keychain-db}"
DAYS_VALID="${DAYS_VALID:-3650}"
P12_PASSWORD="${P12_PASSWORD:-paste-deck-local-codesign}"

echo "🔎 Checking for existing code signing identity: ${IDENTITY_NAME}"
if security find-identity -v -p codesigning | grep -F "\"${IDENTITY_NAME}\"" >/dev/null; then
    echo "✅ Identity already exists."
    security find-identity -v -p codesigning | grep -F "\"${IDENTITY_NAME}\""
    exit 0
fi

if [ ! -f "$KEYCHAIN" ]; then
    echo "❌ Keychain not found: $KEYCHAIN"
    echo "Set KEYCHAIN_PATH to the login keychain path and rerun this script."
    exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

OPENSSL_CONFIG="$TMP_DIR/codesign.cnf"
CERT_PATH="$TMP_DIR/codesign.crt"
KEY_PATH="$TMP_DIR/codesign.key"
P12_PATH="$TMP_DIR/codesign.p12"

cat > "$OPENSSL_CONFIG" << EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = codesign_ext

[ dn ]
CN = ${IDENTITY_NAME}

[ codesign_ext ]
basicConstraints = critical,CA:true,pathlen:0
keyUsage = critical,digitalSignature,keyCertSign
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

echo "🔐 Creating self-signed code signing certificate..."
openssl req \
    -new \
    -x509 \
    -newkey rsa:2048 \
    -sha256 \
    -days "$DAYS_VALID" \
    -nodes \
    -keyout "$KEY_PATH" \
    -out "$CERT_PATH" \
    -config "$OPENSSL_CONFIG"

openssl pkcs12 \
    -legacy \
    -export \
    -inkey "$KEY_PATH" \
    -in "$CERT_PATH" \
    -name "$IDENTITY_NAME" \
    -out "$P12_PATH" \
    -passout "pass:$P12_PASSWORD"

echo "📥 Importing certificate into login keychain..."
security import "$P12_PATH" \
    -k "$KEYCHAIN" \
    -P "$P12_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security

echo "🤝 Trusting certificate for code signing..."
security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$KEYCHAIN" \
    "$CERT_PATH"

echo "🔑 Allowing codesign to use the private key without repeated prompts..."
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "" \
    "$KEYCHAIN" >/dev/null 2>&1 || {
        echo "⚠️  Could not update key partition list automatically."
        echo "   If codesign prompts for key access later, choose Always Allow."
    }

echo ""
echo "✅ Local code signing identity created:"
security find-identity -v -p codesigning | grep -F "\"${IDENTITY_NAME}\"" || true
echo ""
echo "Next:"
echo "  bash scripts/build-dmg.sh"
