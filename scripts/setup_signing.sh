#!/bin/zsh
#
# Creates a self-signed code signing certificate for Sift development.
# Run this ONCE — the certificate persists in your login keychain.
# This gives Sift a stable identity so macOS remembers permission grants across rebuilds.
#
# Usage: ./scripts/setup_signing.sh
#

set -euo pipefail

CERT_NAME="Sift Development"

# Check if it already exists
if security find-identity -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
  echo "Certificate '$CERT_NAME' already exists. Nothing to do."
  exit 0
fi

echo "Creating self-signed code signing certificate: '$CERT_NAME'"
echo ""

# Generate key and certificate
openssl req -x509 -newkey rsa:2048 \
  -keyout /tmp/sift-key.pem -out /tmp/sift-cert.pem \
  -days 3650 -nodes \
  -subj "/CN=$CERT_NAME" \
  -addext "keyUsage=digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" 2>/dev/null

# Convert to p12 for keychain import (needs a non-empty password)
openssl pkcs12 -export \
  -out /tmp/sift-cert.p12 \
  -inkey /tmp/sift-key.pem \
  -in /tmp/sift-cert.pem \
  -passout pass:sift 2>/dev/null

# Import into login keychain (may prompt for keychain password)
security import /tmp/sift-cert.p12 \
  -k ~/Library/Keychains/login.keychain-db \
  -T /usr/bin/codesign \
  -P sift

# Trust the certificate for code signing
security add-trusted-cert -d -r trustRoot -p codeSign \
  -k ~/Library/Keychains/login.keychain-db \
  /tmp/sift-cert.pem 2>/dev/null || true

# Clean up temp files
rm -f /tmp/sift-key.pem /tmp/sift-cert.pem /tmp/sift-cert.p12

echo ""
echo "Done! Certificate '$CERT_NAME' installed."
echo "Sift will now keep a stable identity — macOS will remember your permission grants."
echo ""
echo "Rebuild with: ./scripts/build_and_launch_local_app.sh"
