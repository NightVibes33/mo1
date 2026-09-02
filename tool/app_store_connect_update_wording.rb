#!/usr/bin/env ruby
# frozen_string_literal: true

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'time'
require 'uri'

API_HOST = 'api.appstoreconnect.apple.com'
BUNDLE_ID = ENV.fetch('DOPI_APP_BUNDLE_ID', 'app.mo1.player.39A8Q3T3TR')
PLATFORM = ENV.fetch('DOPI_PLATFORM', 'IOS')
LOCALE = ENV.fetch('DOPI_APP_LOCALE', 'en-US')
APP_DESCRIPTION = ENV.fetch(
  'DOPI_APP_DESCRIPTION',
  'doPi is a retro music player for iPhone and iPad built for personal music libraries. Import MP3 files, connect Apple Music, browse albums with a visual carousel, view lyrics, tune playback with an equalizer, and use smooth song transitions in a focused player built for music fans.'
)
APP_KEYWORDS = ENV.fetch('DOPI_APP_KEYWORDS', 'music player,mp3,apple music,album carousel,lyrics,equalizer,audio player')
SUPPORT_URL = ENV.fetch('DOPI_SUPPORT_URL', 'https://github.com/NightVibes33/mo1')
BETA_DESCRIPTION = ENV.fetch(
  'DOPI_BETA_APP_DESCRIPTION',
  'doPi is a retro music player for iPhone and iPad. Test MP3 import, Apple Music library browsing, album carousel, lyrics, equalizer controls, song transitions, and radial navigation.'
)
REVIEW_NOTES = ENV.fetch(
  'DOPI_REVIEW_NOTES',
  'No demo account is required. Please test local MP3 import, Apple Music connection, playback, lyrics, equalizer, album carousel, and song transitions.'
)
PRIVACY_POLICY_URL = ENV.fetch('DOPI_PRIVACY_POLICY_URL', 'https://github.com/NightVibes33/mo1/blob/main/privacy-policy.md')
BETA_FEEDBACK_EMAIL = ENV.fetch('DOPI_BETA_FEEDBACK_EMAIL', 'bobbytatum12345@gmail.com')

KEY_ID = ENV.fetch('APP_STORE_CONNECT_KEY_ID')
ISSUER_ID = ENV.fetch('APP_STORE_CONNECT_ISSUER_ID')
PRIVATE_KEY = ENV.fetch('APP_STORE_CONNECT_API_KEY_P8')

if PRIVATE_KEY.strip.empty? || KEY_ID.strip.empty? || ISSUER_ID.strip.empty?
  warn 'Missing App Store Connect API key env.'
  exit 1
end

def b64url(data)
  Base64.urlsafe_encode64(data).delete('=')
end

def der_signature_to_raw(der_signature)
  sequence = OpenSSL::ASN1.decode(der_signature)
  raise 'Unexpected ECDSA signature format' unless sequence.is_a?(OpenSSL::ASN1::Sequence) && sequence.value.size == 2

  sequence.value.map do |integer|
    hex = integer.value.to_s(16)
    hex = "0#{hex}" if hex.length.odd?
    [hex].pack('H*').rjust(32, "\0")[-32, 32]
  end.join
end

def jwt
  now = Time.now.to_i
  header = { alg: 'ES256', kid: KEY_ID, typ: 'JWT' }
  payload = { iss: ISSUER_ID, iat: now, exp: now + (20 * 60), aud: 'appstoreconnect-v1' }
  signing_input = [b64url(JSON.generate(header)), b64url(JSON.generate(payload))].join('.')
  key = OpenSSL::PKey.read(PRIVATE_KEY.gsub('\\n', "\n"))
  signature_der = key.sign(OpenSSL::Digest.new('SHA256'), signing_input)
  signature = der_signature_to_raw(signature_der)
  "#{signing_input}.#{b64url(signature)}"
end

TOKEN = jwt

def api_request(method, path, query: nil, body: nil, allow: nil)
  uri = URI::HTTPS.build(host: API_HOST, path: path)
  uri.query = URI.encode_www_form(query) if query && !query.empty?

  klass = case method
          when :get then Net::HTTP::Get
          when :post then Net::HTTP::Post
          when :patch then Net::HTTP::Patch
          else raise "Unsupported HTTP method #{method}"
          end

  request = klass.new(uri)
  request['Authorization'] = "Bearer #{TOKEN}"
  request['Content-Type'] = 'application/json'
  request['Accept'] = 'application/json'
  request.body = JSON.generate(body) if body

  Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    response = http.request(request)
    return {} if response.code.to_i == 204

    parsed = response.body.nil? || response.body.empty? ? {} : JSON.parse(response.body)
    ok = response.code.to_i.between?(200, 299) || Array(allow).include?(response.code.to_i)
    unless ok
      warn "#{method.to_s.upcase} #{path} failed with HTTP #{response.code}"
      warn JSON.pretty_generate(parsed)
      exit 1
    end
    parsed
  end
end

def attributes(record)
  record.fetch('attributes', {}) || {}
end

def included(response, type)
  response.fetch('included', []).select { |item| item['type'] == type }
end

app_response = api_request(:get, '/v1/apps', query: {
  'filter[bundleId]' => BUNDLE_ID,
  'fields[apps]' => 'name,bundleId,sku',
  'limit' => '1'
})
app = app_response.fetch('data', []).first
unless app
  warn "No app found for bundle id #{BUNDLE_ID}."
  exit 1
end
app_id = app.fetch('id')
puts "App: #{attributes(app)['name']} (#{BUNDLE_ID}) id=#{app_id}"

version_response = api_request(:get, "/v1/apps/#{app_id}/appStoreVersions", query: {
  'filter[platform]' => PLATFORM,
  'include' => 'appStoreVersionLocalizations,appStoreReviewDetail',
  'fields[appStoreVersions]' => 'platform,versionString,appStoreState,appVersionState,appStoreVersionLocalizations,appStoreReviewDetail',
  'fields[appStoreVersionLocalizations]' => 'locale,description,keywords,supportUrl',
  'fields[appStoreReviewDetails]' => 'notes,demoAccountRequired',
  'limit' => '50'
})
version = version_response.fetch('data', []).find do |candidate|
  attrs = attributes(candidate)
  %w[WAITING_FOR_REVIEW PREPARE_FOR_SUBMISSION READY_FOR_REVIEW IN_REVIEW DEVELOPER_REJECTED REJECTED METADATA_REJECTED].include?(attrs['appStoreState'].to_s) ||
    %w[WAITING_FOR_REVIEW PREPARE_FOR_SUBMISSION READY_FOR_REVIEW IN_REVIEW DEVELOPER_REJECTED REJECTED METADATA_REJECTED].include?(attrs['appVersionState'].to_s)
end || version_response.fetch('data', []).first
unless version
  warn 'No App Store version found.'
  exit 1
end
version_id = version.fetch('id')
version_attrs = attributes(version)
puts "Using App Store version #{version_attrs['versionString']} state=#{version_attrs['appStoreState'] || version_attrs['appVersionState']} id=#{version_id}."

localization = included(version_response, 'appStoreVersionLocalizations').find { |item| attributes(item)['locale'] == LOCALE } || included(version_response, 'appStoreVersionLocalizations').first
if localization
  puts "Updating App Store wording for #{attributes(localization)['locale'] || LOCALE}."
  api_request(:patch, "/v1/appStoreVersionLocalizations/#{localization.fetch('id')}", body: {
    data: {
      type: 'appStoreVersionLocalizations',
      id: localization.fetch('id'),
      attributes: {
        description: APP_DESCRIPTION,
        keywords: APP_KEYWORDS,
        supportUrl: SUPPORT_URL
      }
    }
  })
else
  warn 'No App Store localization found; unable to patch listing wording.'
end

review_detail = included(version_response, 'appStoreReviewDetails').first
if review_detail
  puts 'Updating App Review notes wording.'
  api_request(:patch, "/v1/appStoreReviewDetails/#{review_detail.fetch('id')}", body: {
    data: {
      type: 'appStoreReviewDetails',
      id: review_detail.fetch('id'),
      attributes: {
        demoAccountRequired: false,
        notes: REVIEW_NOTES
      }
    }
  })
end

beta_localizations = api_request(:get, "/v1/apps/#{app_id}/betaAppLocalizations", query: {
  'fields[betaAppLocalizations]' => 'feedbackEmail,privacyPolicyUrl,description,locale,app',
  'limit' => '200'
})
beta_localization = beta_localizations.fetch('data', []).find { |item| attributes(item)['locale'] == LOCALE } || beta_localizations.fetch('data', []).first
if beta_localization
  puts "Updating TestFlight beta wording for #{attributes(beta_localization)['locale'] || LOCALE}."
  api_request(:patch, "/v1/betaAppLocalizations/#{beta_localization.fetch('id')}", body: {
    data: {
      type: 'betaAppLocalizations',
      id: beta_localization.fetch('id'),
      attributes: {
        description: BETA_DESCRIPTION,
        feedbackEmail: BETA_FEEDBACK_EMAIL,
        privacyPolicyUrl: PRIVACY_POLICY_URL
      }
    }
  })
end

beta_review_details = api_request(:get, '/v1/betaAppReviewDetails', query: {
  'filter[app]' => app_id,
  'fields[betaAppReviewDetails]' => 'demoAccountRequired,notes,app',
  'limit' => '1'
}, allow: [400, 404])
beta_review_detail = beta_review_details.fetch('data', []).first
if beta_review_detail
  puts 'Updating Beta App Review notes wording.'
  api_request(:patch, "/v1/betaAppReviewDetails/#{beta_review_detail.fetch('id')}", body: {
    data: {
      type: 'betaAppReviewDetails',
      id: beta_review_detail.fetch('id'),
      attributes: {
        demoAccountRequired: false,
        notes: REVIEW_NOTES
      }
    }
  })
end

puts 'DONE wording-only App Store Connect update.'
