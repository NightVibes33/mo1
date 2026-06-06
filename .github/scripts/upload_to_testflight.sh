#!/usr/bin/env bash
set -euo pipefail

: "${IPA_PATH:?IPA_PATH is required}"
: "${APP_STORE_CONNECT_API_KEY_P8:?APP_STORE_CONNECT_API_KEY_P8 is required}"
: "${APP_STORE_CONNECT_KEY_ID:?APP_STORE_CONNECT_KEY_ID is required}"
: "${APP_STORE_CONNECT_ISSUER_ID:?APP_STORE_CONNECT_ISSUER_ID is required}"

mkdir -p private_keys
KEY_PATH="${PWD}/private_keys/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
printf '%s' "${APP_STORE_CONNECT_API_KEY_P8}" > "${KEY_PATH}"
export API_PRIVATE_KEYS_DIR="${PWD}/private_keys"

WORK_DIR="$(mktemp -d)"
unzip -q "${IPA_PATH}" -d "${WORK_DIR}/ipa"
INFO_PLIST="$(find "${WORK_DIR}/ipa/Payload" -maxdepth 2 -name Info.plist -path '*.app/Info.plist' -print -quit)"
if [ -z "${INFO_PLIST}" ]; then
  echo "No app Info.plist found inside IPA" >&2
  exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO_PLIST}")"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
BUNDLE_SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
export BUNDLE_ID

JWT="$(KEY_ID="${APP_STORE_CONNECT_KEY_ID}" ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID}" KEY_PATH="${KEY_PATH}" ruby <<'RUBY'
require 'base64'
require 'json'
require 'openssl'

def b64(data)
  Base64.urlsafe_encode64(data).delete('=')
end

header = { alg: 'ES256', kid: ENV.fetch('KEY_ID'), typ: 'JWT' }
payload = { iss: ENV.fetch('ISSUER_ID'), exp: Time.now.to_i + 20 * 60, aud: 'appstoreconnect-v1' }
data = "#{b64(header.to_json)}.#{b64(payload.to_json)}"
key = OpenSSL::PKey.read(File.read(ENV.fetch('KEY_PATH')))
der = key.sign(OpenSSL::Digest::SHA256.new, data)
asn1 = OpenSSL::ASN1.decode(der)
raw = asn1.value.map do |integer|
  integer.value.to_i.to_s(16).rjust(64, '0')[-64, 64]
end.join
puts "#{data}.#{b64([raw].pack('H*'))}"
RUBY
)"

APP_JSON="${WORK_DIR}/app.json"
curl -fsS \
  -H "Authorization: Bearer ${JWT}" \
  -H 'Accept: application/json' \
  "https://api.appstoreconnect.apple.com/v1/apps?filter%5BbundleId%5D=${BUNDLE_ID}" \
  -o "${APP_JSON}"

APP_INFO="$(ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  app = data.fetch("data").first
  unless app
    warn "No App Store Connect app record found for bundle ID #{ENV.fetch("BUNDLE_ID")}. Create the app record with this exact bundle ID, then rerun."
    exit 2
  end
  attrs = app.fetch("attributes")
  apple_id = attrs["appleId"] || app.fetch("id")
  name = attrs.fetch("name")
  puts [app.fetch("id"), apple_id, name].join("\t")
' "${APP_JSON}")"

ASC_APP_ID="$(printf '%s' "${APP_INFO}" | cut -f1)"
APPLE_ID="$(printf '%s' "${APP_INFO}" | cut -f2)"
APP_NAME="$(printf '%s' "${APP_INFO}" | cut -f3-)"

echo "Matched App Store Connect app '${APP_NAME}' (${ASC_APP_ID}) for ${BUNDLE_ID}; Apple ID ${APPLE_ID}; version ${BUNDLE_SHORT_VERSION} (${BUNDLE_VERSION})."

xcrun altool \
  --upload-app \
  -f "${IPA_PATH}" \
  --type ios \
  --apple-id "${APPLE_ID}" \
  --apiKey "${APP_STORE_CONNECT_KEY_ID}" \
  --apiIssuer "${APP_STORE_CONNECT_ISSUER_ID}"
