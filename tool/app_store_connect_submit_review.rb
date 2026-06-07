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
REVIEW_CONTACT_FIRST_NAME = ENV['DOPI_REVIEW_CONTACT_FIRST_NAME']
REVIEW_CONTACT_LAST_NAME = ENV['DOPI_REVIEW_CONTACT_LAST_NAME']
REVIEW_CONTACT_EMAIL = ENV['DOPI_REVIEW_CONTACT_EMAIL'] || ENV['DOPI_BETA_CONTACT_EMAIL'] || ENV['DOPI_BETA_FEEDBACK_EMAIL']
REVIEW_CONTACT_PHONE = ENV['DOPI_REVIEW_CONTACT_PHONE'] || ENV['DOPI_BETA_CONTACT_PHONE']
REVIEW_NOTES = ENV.fetch(
  'DOPI_REVIEW_NOTES',
  'No demo account is required. Please test local MP3 import, Apple Music connection, playback, lyrics, equalizer, album carousel, and song transitions.'
)
USE_LATEST_VALID_BUILD = ENV.fetch('DOPI_USE_LATEST_VALID_BUILD', 'true').casecmp('true').zero?
TARGET_BUILD_VERSION = ENV['DOPI_TARGET_BUILD_VERSION']
USES_NON_EXEMPT_ENCRYPTION = ENV.fetch('DOPI_USES_NON_EXEMPT_ENCRYPTION', 'false').casecmp('true').zero?

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
          when :delete then Net::HTTP::Delete
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

def present(value)
  value.to_s.strip.empty? ? nil : value
end


def active_submission_state?(state)
  %w[READY_FOR_REVIEW WAITING_FOR_REVIEW IN_REVIEW UNRESOLVED_ISSUES].include?(state.to_s)
end

def cancellable_submission_state?(state)
  %w[READY_FOR_REVIEW WAITING_FOR_REVIEW].include?(state.to_s)
end

def sorted_valid_builds(app_id)
  response = api_request(:get, "/v1/apps/#{app_id}/builds", query: {
    'fields[builds]' => 'version,uploadedDate,processingState,expired,usesNonExemptEncryption',
    'limit' => '200'
  })

  response.fetch('data', []).select do |build|
    attrs = attributes(build)
    !attrs['expired'] && attrs['processingState'].to_s.upcase == 'VALID'
  end.sort_by do |build|
    Time.parse(attributes(build)['uploadedDate'].to_s) rescue Time.at(0)
  end.reverse
end

def latest_review_submission(app_id, platform)
  response = api_request(:get, '/v1/reviewSubmissions', query: {
    'filter[app]' => app_id,
    'filter[platform]' => platform,
    'include' => 'items,appStoreVersionForReview',
    'fields[reviewSubmissions]' => 'platform,submittedDate,state,items,appStoreVersionForReview',
    'fields[reviewSubmissionItems]' => 'state,appStoreVersion',
    'fields[appStoreVersions]' => 'versionString,appStoreState,appVersionState,platform',
    'limit' => '50',
    'limit[items]' => '50'
  })
  submissions = response.fetch('data', [])
  active = submissions.find { |item| active_submission_state?(attributes(item)['state']) }
  [active, response]
end

def cancel_app_store_version_submission(version, submission)
  submission_id = submission.fetch('id')
  state = attributes(submission)['state']
  unless cancellable_submission_state?(state)
    warn "Review submission #{submission_id} is state=#{state}; not safe to cancel automatically."
    exit 1
  end

  app_store_version_submission_id = version.dig('relationships', 'appStoreVersionSubmission', 'data', 'id')
  unless present(app_store_version_submission_id)
    warn "No appStoreVersionSubmission relationship found for App Store version #{version.fetch('id')}."
    exit 1
  end

  puts "Deleting App Store version submission #{app_store_version_submission_id} to remove version from review."
  response = api_request(:delete, "/v1/appStoreVersionSubmissions/#{app_store_version_submission_id}", allow: [403, 404, 409])
  return if response.empty?

  errors = response['errors'] || []
  return if errors.empty?

  warn "App Store version submission delete failed: #{JSON.generate(errors)}"
  exit 1
end

app_response = api_request(:get, '/v1/apps', query: {
  'filter[bundleId]' => BUNDLE_ID,
  'fields[apps]' => 'name,bundleId,sku,primaryLocale',
  'limit' => '1'
})
app = app_response.fetch('data', []).first
unless app
  warn "No App Store Connect app found for bundle id #{BUNDLE_ID}."
  exit 1
end
app_id = app.fetch('id')
puts "App: #{attributes(app)['name']} (#{BUNDLE_ID}) id=#{app_id}"

version_response = api_request(:get, "/v1/apps/#{app_id}/appStoreVersions", query: {
  'filter[platform]' => PLATFORM,
  'include' => 'build,appStoreReviewDetail,appStoreVersionLocalizations,appStoreVersionSubmission',
  'fields[appStoreVersions]' => 'platform,versionString,appStoreState,appVersionState,createdDate,build,appStoreReviewDetail,appStoreVersionLocalizations,appStoreVersionSubmission',
  'fields[builds]' => 'version,uploadedDate,processingState,expired,usesNonExemptEncryption',
  'fields[appStoreReviewDetails]' => 'contactFirstName,contactLastName,contactPhone,contactEmail,demoAccountRequired,notes',
  'fields[appStoreVersionLocalizations]' => 'locale,description,keywords,supportUrl',
  'limit' => '50'
})
versions = version_response.fetch('data', [])
preferred_states = %w[PREPARE_FOR_SUBMISSION READY_FOR_REVIEW WAITING_FOR_REVIEW DEVELOPER_REJECTED REJECTED METADATA_REJECTED]
version = versions.find do |candidate|
  attrs = attributes(candidate)
  preferred_states.include?(attrs['appStoreState'].to_s) || preferred_states.include?(attrs['appVersionState'].to_s)
end || versions.first
unless version
  warn "No #{PLATFORM} App Store version found."
  exit 1
end
version_id = version.fetch('id')
version_attrs = attributes(version)
version_state = version_attrs['appStoreState'] || version_attrs['appVersionState']
puts "Using App Store version #{version_attrs['versionString']} state=#{version_state} id=#{version_id}."

build_id = version.dig('relationships', 'build', 'data', 'id')
build = included(version_response, 'builds').find { |item| item['id'] == build_id }
if build
  puts "Attached build: #{attributes(build)['version']} processing=#{attributes(build)['processingState']} encryption=#{attributes(build)['usesNonExemptEncryption'].inspect}."
else
  warn 'No build is attached to the selected App Store version.'
end


target_build = nil
if USE_LATEST_VALID_BUILD
  valid_builds = sorted_valid_builds(app_id)
  puts 'Recent valid builds:'
  valid_builds.take(8).each do |candidate|
    attrs = attributes(candidate)
    puts "- #{attrs['version']} uploaded #{attrs['uploadedDate']} encryption=#{attrs['usesNonExemptEncryption'].inspect}"
  end

  target_build = if present(TARGET_BUILD_VERSION)
                   valid_builds.find { |candidate| attributes(candidate)['version'].to_s == TARGET_BUILD_VERSION.to_s }
                 else
                   valid_builds.first
                 end

  unless target_build
    warn "No valid build found#{TARGET_BUILD_VERSION ? " for #{TARGET_BUILD_VERSION}" : ''}."
    exit 1
  end

  target_attrs = attributes(target_build)
  current_build_version = build ? attributes(build)['version'].to_s : nil
  puts "Target App Store build: #{target_attrs['version']} uploaded #{target_attrs['uploadedDate']}."

  if current_build_version != target_attrs['version'].to_s
    submission, = latest_review_submission(app_id, PLATFORM)
    if submission && active_submission_state?(attributes(submission)['state'])
      cancel_app_store_version_submission(version, submission)
      sleep 5
    end

    puts "Setting export compliance on target build #{target_attrs['version']}: usesNonExemptEncryption=#{USES_NON_EXEMPT_ENCRYPTION}."
    compliance_response = api_request(:patch, "/v1/builds/#{target_build.fetch('id')}", body: {
      data: {
        type: 'builds',
        id: target_build.fetch('id'),
        attributes: {
          usesNonExemptEncryption: USES_NON_EXEMPT_ENCRYPTION
        }
      }
    }, allow: [409])
    compliance_errors = compliance_response['errors'] || []
    unless compliance_errors.empty? || compliance_errors.all? { |error| error['detail'].to_s.include?('already set') }
      warn "Export compliance update failed: #{JSON.generate(compliance_errors)}"
      exit 1
    end

    puts "Attaching build #{target_attrs['version']} to App Store version #{version_attrs['versionString']}."
    api_request(:patch, "/v1/appStoreVersions/#{version_id}/relationships/build", body: {
      data: {
        type: 'builds',
        id: target_build.fetch('id')
      }
    })

    build = target_build
    build_id = target_build.fetch('id')
  else
    puts "App Store version already has target build #{current_build_version} attached."
  end
end

beta_response = api_request(:get, '/v1/betaAppReviewDetails', query: {
  'filter[app]' => app_id,
  'fields[betaAppReviewDetails]' => 'contactFirstName,contactLastName,contactPhone,contactEmail,demoAccountRequired,notes',
  'limit' => '1'
}, allow: [400, 404])
beta_attrs = attributes(beta_response.fetch('data', []).first || {})

review_detail = included(version_response, 'appStoreReviewDetails').first
unless review_detail
  detail_response = api_request(:get, "/v1/appStoreVersions/#{version_id}/appStoreReviewDetail", query: {
    'fields[appStoreReviewDetails]' => 'contactFirstName,contactLastName,contactPhone,contactEmail,demoAccountRequired,notes'
  }, allow: [404])
  review_detail = detail_response['data']
end

review_attrs_current = attributes(review_detail || {})
review_attrs = {
  contactFirstName: present(REVIEW_CONTACT_FIRST_NAME) || present(review_attrs_current['contactFirstName']) || present(beta_attrs['contactFirstName']) || 'Aditya',
  contactLastName: present(REVIEW_CONTACT_LAST_NAME) || present(review_attrs_current['contactLastName']) || present(beta_attrs['contactLastName']) || 'R',
  contactEmail: present(REVIEW_CONTACT_EMAIL) || present(review_attrs_current['contactEmail']) || present(beta_attrs['contactEmail']),
  contactPhone: present(REVIEW_CONTACT_PHONE) || present(review_attrs_current['contactPhone']) || present(beta_attrs['contactPhone']),
  demoAccountRequired: false,
  notes: REVIEW_NOTES
}
missing_review = %i[contactFirstName contactLastName contactEmail contactPhone].select { |key| review_attrs[key].nil? }
unless missing_review.empty?
  warn "App Review contact info missing: #{missing_review.join(', ')}. Add DOPI_REVIEW_CONTACT_* env values."
  exit 1
end

if review_detail
  review_detail_id = review_detail.fetch('id')
  puts 'Setting App Review contact details.'
  api_request(:patch, "/v1/appStoreReviewDetails/#{review_detail_id}", body: {
    data: {
      type: 'appStoreReviewDetails',
      id: review_detail_id,
      attributes: review_attrs
    }
  })
else
  puts 'Creating App Review contact details.'
  api_request(:post, '/v1/appStoreReviewDetails', body: {
    data: {
      type: 'appStoreReviewDetails',
      attributes: review_attrs,
      relationships: {
        appStoreVersion: { data: { type: 'appStoreVersions', id: version_id } }
      }
    }
  })
end

submission, submissions_response = latest_review_submission(app_id, PLATFORM)

if submission
  submission_id = submission.fetch('id')
  puts "Using existing review submission #{submission_id} state=#{attributes(submission)['state']}."
else
  puts 'Creating review submission.'
  submission = api_request(:post, '/v1/reviewSubmissions', body: {
    data: {
      type: 'reviewSubmissions',
      attributes: { platform: PLATFORM },
      relationships: {
        app: { data: { type: 'apps', id: app_id } }
      }
    }
  }).fetch('data')
  submission_id = submission.fetch('id')
  puts "Created review submission #{submission_id}."
end

items_response = api_request(:get, "/v1/reviewSubmissions/#{submission_id}/items", query: {
  'include' => 'appStoreVersion',
  'fields[reviewSubmissionItems]' => 'state,appStoreVersion',
  'fields[appStoreVersions]' => 'versionString,appStoreState,appVersionState,platform',
  'limit' => '50'
})
existing_item = items_response.fetch('data', []).find do |item|
  item.dig('relationships', 'appStoreVersion', 'data', 'id') == version_id
end

if existing_item
  puts "App Store version already attached as review item #{existing_item.fetch('id')} state=#{attributes(existing_item)['state']}."
else
  puts "Adding App Store version #{version_attrs['versionString']} to review submission."
  item = api_request(:post, '/v1/reviewSubmissionItems', body: {
    data: {
      type: 'reviewSubmissionItems',
      relationships: {
        reviewSubmission: { data: { type: 'reviewSubmissions', id: submission_id } },
        appStoreVersion: { data: { type: 'appStoreVersions', id: version_id } }
      }
    }
  }).fetch('data')
  puts "Created review submission item #{item.fetch('id')}."
end

fresh_submission = api_request(:get, "/v1/reviewSubmissions/#{submission_id}", query: {
  'fields[reviewSubmissions]' => 'platform,submittedDate,state,items,appStoreVersionForReview'
}).fetch('data')
fresh_state = attributes(fresh_submission)['state']
puts "Review submission state before submit: #{fresh_state}."

if %w[WAITING_FOR_REVIEW IN_REVIEW].include?(fresh_state.to_s)
  puts "DONE App Store review submission already submitted: state=#{fresh_state}."
else
  puts 'Submitting App Store review submission.'
  submitted = api_request(:patch, "/v1/reviewSubmissions/#{submission_id}", body: {
    data: {
      type: 'reviewSubmissions',
      id: submission_id,
      attributes: { submitted: true }
    }
  }).fetch('data')
  puts "DONE App Store review submission state=#{attributes(submitted)['state']} submittedDate=#{attributes(submitted)['submittedDate']}."
end
