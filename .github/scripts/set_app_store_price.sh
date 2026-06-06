#!/usr/bin/env bash
set -euo pipefail

: "${APP_STORE_CONNECT_API_KEY_P8:?APP_STORE_CONNECT_API_KEY_P8 is required}"
: "${APP_STORE_CONNECT_KEY_ID:?APP_STORE_CONNECT_KEY_ID is required}"
: "${APP_STORE_CONNECT_ISSUER_ID:?APP_STORE_CONNECT_ISSUER_ID is required}"
: "${APP_BUNDLE_ID:?APP_BUNDLE_ID is required}"
CUSTOMER_PRICE="${CUSTOMER_PRICE:-0.99}"
BASE_TERRITORY="${BASE_TERRITORY:-USA}"

mkdir -p private_keys
KEY_PATH="${PWD}/private_keys/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
printf '%s' "${APP_STORE_CONNECT_API_KEY_P8}" > "${KEY_PATH}"

WORK_DIR="$(mktemp -d)"
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

api_get() {
  local url="$1"
  local output="$2"
  curl -fsS \
    -H "Authorization: Bearer ${JWT}" \
    -H 'Accept: application/json' \
    "${url}" \
    -o "${output}"
}

api_post() {
  local url="$1"
  local input="$2"
  local output="$3"
  curl -sS \
    -w '%{http_code}' \
    -H "Authorization: Bearer ${JWT}" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -X POST \
    --data-binary "@${input}" \
    "${url}" \
    -o "${output}"
}

APP_JSON="${WORK_DIR}/app.json"
api_get "https://api.appstoreconnect.apple.com/v1/apps?filter%5BbundleId%5D=${APP_BUNDLE_ID}" "${APP_JSON}"
APP_ID="$(ruby -rjson -e 'data = JSON.parse(File.read(ARGV[0])); app = data.fetch("data").first; abort("No App Store Connect app found for bundle #{ENV.fetch("APP_BUNDLE_ID")}") unless app; puts app.fetch("id")' "${APP_JSON}")"
APP_NAME="$(ruby -rjson -e 'data = JSON.parse(File.read(ARGV[0])); app = data.fetch("data").first; puts app.fetch("attributes").fetch("name")' "${APP_JSON}")"

POINTS_JSON="${WORK_DIR}/price-points.json"
api_get "https://api.appstoreconnect.apple.com/v1/apps/${APP_ID}/appPricePoints?filter%5Bterritory%5D=${BASE_TERRITORY}&fields%5BappPricePoints%5D=customerPrice,proceeds,territory&limit=200" "${POINTS_JSON}"
PRICE_POINT_ID="$(CUSTOMER_PRICE="${CUSTOMER_PRICE}" ruby -rjson -e '
  data = JSON.parse(File.read(ARGV[0]))
  wanted = ENV.fetch("CUSTOMER_PRICE").to_f
  point = data.fetch("data").find do |item|
    attrs = item.fetch("attributes", {})
    price = attrs["customerPrice"] || attrs["price"]
    price && (price.to_f - wanted).abs < 0.001
  end
  unless point
    available = data.fetch("data").map { |item| item.fetch("attributes", {})["customerPrice"] }.compact.uniq.take(20)
    warn "No price point found for $#{format("%.2f", wanted)}. First available customer prices: #{available.join(", ")}"
    exit 2
  end
  puts point.fetch("id")
' "${POINTS_JSON}")"

PAYLOAD="${WORK_DIR}/price-schedule.json"
APP_ID="${APP_ID}" PRICE_POINT_ID="${PRICE_POINT_ID}" BASE_TERRITORY="${BASE_TERRITORY}" ruby <<'RUBY' > "${PAYLOAD}"
require 'json'
price_id = '${newprice-0}'
puts JSON.pretty_generate({
  data: {
    type: 'appPriceSchedules',
    attributes: {},
    relationships: {
      app: { data: { type: 'apps', id: ENV.fetch('APP_ID') } },
      baseTerritory: { data: { type: 'territories', id: ENV.fetch('BASE_TERRITORY') } },
      manualPrices: { data: [{ type: 'appPrices', id: price_id }] }
    }
  },
  included: [{
    type: 'appPrices',
    id: price_id,
    attributes: {
      startDate: nil,
      endDate: nil
    },
    relationships: {
      appPricePoint: { data: { type: 'appPricePoints', id: ENV.fetch('PRICE_POINT_ID') } },
      territory: { data: { type: 'territories', id: ENV.fetch('BASE_TERRITORY') } }
    }
  }]
})
RUBY

RESPONSE="${WORK_DIR}/price-response.json"
STATUS="$(api_post 'https://api.appstoreconnect.apple.com/v1/appPriceSchedules' "${PAYLOAD}" "${RESPONSE}")"
if [ "${STATUS}" -lt 200 ] || [ "${STATUS}" -ge 300 ]; then
  echo "App Store price update failed with HTTP ${STATUS}" >&2
  cat "${RESPONSE}" >&2
  exit 1
fi

echo "Set ${APP_NAME} (${APP_BUNDLE_ID}) to paid app price $${CUSTOMER_PRICE} using ${BASE_TERRITORY} price point ${PRICE_POINT_ID}."
