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
APP_NAME = ENV.fetch('DOPI_APP_NAME', 'ClassiPod')
APP_SUBTITLE = ENV.fetch('DOPI_APP_SUBTITLE', 'Retro Click Wheel Music Player')
APP_DESCRIPTION = ENV.fetch(
  'DOPI_APP_DESCRIPTION',
  'ClassiPod turns your iPhone into a retro click-wheel music player for the library you actually own. Spin the wheel to browse your songs, flip through albums in a cover carousel, and play your music the way it used to feel. Import your own MP3 files with no subscription needed, connect your own Apple Music library, or stream from your Navidrome or Jellyfin server. Features a 10-band custom equalizer with presets, time-synced lyrics, editable song info, home screen widgets, lock screen controls, and click-wheel navigation with haptics. No ads. No tracking. Just your music.'
)
APP_KEYWORDS = ENV.fetch(
  'DOPI_APP_KEYWORDS',
  'click wheel,retro,classic,music player,mp3,offline,navidrome,jellyfin,equalizer,lyrics,cover flow'
)
SUPPORT_URL = ENV.fetch('DOPI_SUPPORT_URL', 'https://github.com/NightVibes33/mo1')
BETA_DESCRIPTION = ENV.fetch(
  'DOPI_BETA_APP_DESCRIPTION',
  'ClassiPod is a retro music player for iPhone and iPad. Test MP3 import, Apple Music library browsing, album carousel, lyrics, equalizer controls, song transitions, and radial navigation.'
)
REVIEW_NOTES = ENV.fetch(
  'DOPI_REVIEW_NOTES',
  'No demo account is required. Please test local MP3 import, Apple Music connection, playback, lyrics, equalizer, album carousel, and song transitions.'
)
PRIVACY_POLICY_URL = ENV.fetch('DOPI_PRIVACY_POLICY_URL', 'https://github.com/NightVibes33/mo1/blob/main/privacy-policy.md')
BETA_FEEDBACK_EMAIL = ENV.fetch('DOPI_BETA_FEEDBACK_EMAIL', 'bobbytatum12345@gmail.com')

# Name and subtitle belong on appInfoLocalizations. They are not attributes of
# appStoreVersionLocalizations. ageRatingDeclaration was removed from
# appStoreVersions and is read from appInfos. seventeenPlus was removed from
# the update schema. Rating overrides are not content descriptors.
EDITABLE_STATES = %w[
  WAITING_FOR_REVIEW
  PREPARE_FOR_SUBMISSION
  READY_FOR_REVIEW
  IN_REVIEW
  DEVELOPER_REJECTED
  REJECTED
  METADATA_REJECTED
].freeze
AGE_RATING_ATTRIBUTES = {
  'alcoholTobaccoOrDrugUseOrReferences' => 'NONE',
  'contests' => 'NONE',
  'gamblingSimulated' => 'NONE',
  'gunsOrOtherWeapons' => 'NONE',
  'horrorOrFearThemes' => 'NONE',
  'matureOrSuggestiveThemes' => 'NONE',
  'medicalOrTreatmentInformation' => 'NONE',
  'profanityOrCrudeHumor' => 'NONE',
  'sexualContentGraphicAndNudity' => 'NONE',
  'sexualContentOrNudity' => 'NONE',
  'violenceCartoonOrFantasy' => 'NONE',
  'violenceRealistic' => 'NONE',
  'violenceRealisticProlongedGraphicOrSadistic' => 'NONE',
  'advertising' => false,
  'ageAssurance' => false,
  'gambling' => false,
  'healthOrWellnessTopics' => false,
  'lootBox' => false,
  'messagingAndChat' => false,
  'parentalControls' => false,
  'socialMedia' => false,
  'socialMediaAgeRestricted' => false,
  'unrestrictedWebAccess' => false,
  'userGeneratedContent' => false,
  'kidsAgeBand' => nil
}.freeze

if APP_NAME.length > 30
  warn "DOPI_APP_NAME is #{APP_NAME.length} characters; the App Store limit is 30."
  exit 1
end
if APP_SUBTITLE.length > 30
  warn "DOPI_APP_SUBTITLE is #{APP_SUBTITLE.length} characters; the App Store limit is 30."
  exit 1
end
if APP_KEYWORDS.length > 100
  warn "DOPI_APP_KEYWORDS is #{APP_KEYWORDS.length} characters; the App Store limit is 100."
  exit 1
end
if APP_DESCRIPTION.length > 4000
  warn "DOPI_APP_DESCRIPTION is #{APP_DESCRIPTION.length} characters; the App Store limit is 4000."
  exit 1
end

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

def editable_state?(record)
  attrs = attributes(record)
  EDITABLE_STATES.include?(attrs['appStoreState'].to_s) ||
    EDITABLE_STATES.include?(attrs['state'].to_s) ||
    EDITABLE_STATES.include?(attrs['appVersionState'].to_s)
end

def preferred_app_info(app_id)
  response = api_request(:get, "/v1/apps/#{app_id}/appInfos", query: {
    'limit' => '20',
    'fields[appInfos]' => 'appStoreState,state'
  })
  infos = response.fetch('data', [])
  infos.find { |item| editable_state?(item) } || infos.first
end

def update_name_and_subtitle(app_id)
  app_info = preferred_app_info(app_id)
  unless app_info
    warn 'No appInfo found; skipping name and subtitle.'
    return
  end

  localizations = api_request(:get, "/v1/appInfos/#{app_info.fetch('id')}/appInfoLocalizations", query: {
    'limit' => '200',
    'fields[appInfoLocalizations]' => 'locale,name,subtitle'
  })
  localization = localizations.fetch('data', []).find { |item| attributes(item)['locale'] == LOCALE } ||
                 localizations.fetch('data', []).first
  unless localization
    warn 'No appInfoLocalization found; skipping name and subtitle.'
    return
  end

  puts "Updating App Store name and subtitle for #{attributes(localization)['locale'] || LOCALE}."
  api_request(:patch, "/v1/appInfoLocalizations/#{localization.fetch('id')}", body: {
    data: {
      type: 'appInfoLocalizations',
      id: localization.fetch('id'),
      attributes: {
        name: APP_NAME,
        subtitle: APP_SUBTITLE
      }
    }
  })
end

def declaration_from_response(response)
  included_item = included(response, 'ageRatingDeclarations').first
  return included_item if included_item

  data = response['data']
  return data if data.is_a?(Hash) && data['type'] == 'ageRatingDeclarations' && data['id']

  relationship = response.dig('data', 'relationships', 'ageRatingDeclaration', 'data')
  return relationship if relationship.is_a?(Hash) && relationship['id']

  nil
end

def fetch_age_rating_declaration(app_id, version_id)
  # Separate from the wording GET. A removed relationship returns 400 and
  # would abort the description update if it were on that request.
  version_attempt = api_request(:get, "/v1/appStoreVersions/#{version_id}", query: {
    'include' => 'ageRatingDeclaration',
    'fields[appStoreVersions]' => 'versionString,ageRatingDeclaration'
  }, allow: [400, 404])
  declaration = declaration_from_response(version_attempt)
  return declaration if declaration

  app_info = preferred_app_info(app_id)
  return nil unless app_info

  info_attempt = api_request(
    :get,
    "/v1/appInfos/#{app_info.fetch('id')}/ageRatingDeclaration",
    allow: [400, 404]
  )
  declaration_from_response(info_attempt)
end

def update_age_rating(app_id, version_id)
  declaration = fetch_age_rating_declaration(app_id, version_id)
  unless declaration
    warn 'No ageRatingDeclaration returned; skipping age rating update.'
    return
  end

  declaration_id = declaration.fetch('id')
  puts "Updating age rating declaration #{declaration_id} to a clean 4+ questionnaire."
  api_request(:patch, "/v1/ageRatingDeclarations/#{declaration_id}", body: {
    data: {
      type: 'ageRatingDeclarations',
      id: declaration_id,
      attributes: AGE_RATING_ATTRIBUTES
    }
  })
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

update_name_and_subtitle(app_id)
update_age_rating(app_id, version_id)

puts 'DONE wording-only App Store Connect update.'
