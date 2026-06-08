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
TARGET_BUILD_VERSION = ENV['DOPI_TARGET_BUILD_VERSION']&.strip
GROUP_NAME = ENV.fetch('DOPI_BETA_GROUP_NAME', 'døPi Public Beta')
LOCALE = ENV.fetch('DOPI_APP_LOCALE', 'en-US')
BETA_DESCRIPTION = ENV.fetch(
  'DOPI_BETA_APP_DESCRIPTION',
  'døPi is a retro music player for iPhone and iPad. Test MP3 import, Apple Music library browsing, album carousel, lyrics, equalizer controls, song transitions, and radial navigation.'
)
BETA_FEEDBACK_EMAIL = ENV.fetch('DOPI_BETA_FEEDBACK_EMAIL', 'bobbytatum12345@gmail.com')
PRIVACY_POLICY_URL = ENV.fetch('DOPI_PRIVACY_POLICY_URL', 'https://github.com/NightVibes33/mo1/blob/main/privacy-policy.md')
BETA_CONTACT_FIRST_NAME = ENV['DOPI_BETA_CONTACT_FIRST_NAME']
BETA_CONTACT_LAST_NAME = ENV['DOPI_BETA_CONTACT_LAST_NAME']
BETA_CONTACT_EMAIL = ENV['DOPI_BETA_CONTACT_EMAIL'] || BETA_FEEDBACK_EMAIL
BETA_CONTACT_PHONE = ENV['DOPI_BETA_CONTACT_PHONE']
BETA_REVIEW_NOTES = ENV.fetch(
  'DOPI_BETA_REVIEW_NOTES',
  'No demo account is required. Please test local MP3 import, Apple Music connection, playback, lyrics, equalizer, album carousel, and song transitions.'
)
USES_NON_EXEMPT_ENCRYPTION = ENV.fetch('DOPI_USES_NON_EXEMPT_ENCRYPTION', 'false').casecmp('true').zero?

KEY_ID = ENV.fetch('APP_STORE_CONNECT_KEY_ID')
ISSUER_ID = ENV.fetch('APP_STORE_CONNECT_ISSUER_ID')
PRIVATE_KEY = ENV.fetch('APP_STORE_CONNECT_API_KEY_P8')

if PRIVATE_KEY.strip.empty? || KEY_ID.strip.empty? || ISSUER_ID.strip.empty?
  warn 'Missing App Store Connect API key env. Required: APP_STORE_CONNECT_API_KEY_P8, APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID.'
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

def request(method, path, query: nil, body: nil)
  uri = URI::HTTPS.build(host: API_HOST, path: path)
  uri.query = URI.encode_www_form(query) if query && !query.empty?

  req_class = case method
              when :get then Net::HTTP::Get
              when :post then Net::HTTP::Post
              when :patch then Net::HTTP::Patch
              else raise "Unsupported HTTP method #{method}"
              end
  req = req_class.new(uri)
  req['Authorization'] = "Bearer #{TOKEN}"
  req['Content-Type'] = 'application/json'
  req.body = JSON.generate(body) if body

  Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    response = http.request(req)
    return nil if response.code.to_i == 204

    parsed = response.body.nil? || response.body.empty? ? {} : JSON.parse(response.body)
    unless response.code.to_i.between?(200, 299)
      warn "#{method.to_s.upcase} #{path} failed with HTTP #{response.code}"
      warn JSON.pretty_generate(parsed)
      exit 1
    end
    parsed
  end
end

def request_optional(method, path, query: nil, body: nil)
  uri = URI::HTTPS.build(host: API_HOST, path: path)
  uri.query = URI.encode_www_form(query) if query && !query.empty?

  req_class = case method
              when :get then Net::HTTP::Get
              when :post then Net::HTTP::Post
              when :patch then Net::HTTP::Patch
              else raise "Unsupported HTTP method #{method}"
              end
  req = req_class.new(uri)
  req['Authorization'] = "Bearer #{TOKEN}"
  req['Content-Type'] = 'application/json'
  req.body = JSON.generate(body) if body

  Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    response = http.request(req)
    parsed = response.body.nil? || response.body.empty? ? {} : JSON.parse(response.body)
    [response.code.to_i, parsed]
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

apps = request(:get, '/v1/apps', query: {
  'filter[bundleId]' => BUNDLE_ID,
  'fields[apps]' => 'name,bundleId,sku',
  'limit' => '1'
})
app = apps.fetch('data', []).first
unless app
  warn "No App Store Connect app found for bundle id #{BUNDLE_ID}."
  exit 1
end
app_id = app.fetch('id')
app_attrs = attributes(app)
puts "App: #{app_attrs['name'] || '(unknown)'} (#{BUNDLE_ID})"

app_store_versions_for_review = request(:get, "/v1/apps/#{app_id}/appStoreVersions", query: {
  'filter[platform]' => 'IOS',
  'include' => 'appStoreReviewDetail',
  'fields[appStoreVersions]' => 'platform,versionString,appStoreState,appVersionState,createdDate,appStoreReviewDetail',
  'fields[appStoreReviewDetails]' => 'contactFirstName,contactLastName,contactPhone,contactEmail,demoAccountRequired,notes',
  'limit' => '20'
})
app_store_review_attrs = attributes(included(app_store_versions_for_review, 'appStoreReviewDetails').first || {})

beta_review_details = request(:get, '/v1/betaAppReviewDetails', query: {
  'filter[app]' => app_id,
  'fields[betaAppReviewDetails]' => 'contactFirstName,contactLastName,contactPhone,contactEmail,demoAccountRequired,notes,app',
  'limit' => '1'
})
beta_review_detail = beta_review_details.fetch('data', []).first
if beta_review_detail
  current_beta_review_attrs = attributes(beta_review_detail)
  review_attrs = {
    contactFirstName: present(BETA_CONTACT_FIRST_NAME) || present(current_beta_review_attrs['contactFirstName']) || present(app_store_review_attrs['contactFirstName']) || 'Aditya',
    contactLastName: present(BETA_CONTACT_LAST_NAME) || present(current_beta_review_attrs['contactLastName']) || present(app_store_review_attrs['contactLastName']) || 'R',
    contactEmail: present(BETA_CONTACT_EMAIL) || present(current_beta_review_attrs['contactEmail']) || present(app_store_review_attrs['contactEmail']),
    contactPhone: present(BETA_CONTACT_PHONE) || present(current_beta_review_attrs['contactPhone']) || present(app_store_review_attrs['contactPhone']),
    demoAccountRequired: false,
    notes: BETA_REVIEW_NOTES
  }
  missing = %i[contactFirstName contactLastName contactEmail contactPhone].select { |key| review_attrs[key].nil? }
  if missing.empty?
    puts 'Setting Beta App Review contact details.'
    request(:patch, "/v1/betaAppReviewDetails/#{beta_review_detail.fetch('id')}", body: {
      data: {
        type: 'betaAppReviewDetails',
        id: beta_review_detail.fetch('id'),
        attributes: review_attrs
      }
    })
  else
    warn "Beta App Review contact details still missing: #{missing.join(', ')}. Set DOPI_BETA_CONTACT_* workflow env values."
  end
else
  warn 'No Beta App Review detail resource found for this app.'
end

beta_localizations = request(:get, "/v1/apps/#{app_id}/betaAppLocalizations", query: {
  'fields[betaAppLocalizations]' => 'feedbackEmail,marketingUrl,privacyPolicyUrl,tvOsPrivacyPolicy,description,locale,app',
  'limit' => '200'
})
beta_localization = beta_localizations.fetch('data', []).find { |item| attributes(item)['locale'] == LOCALE } || beta_localizations.fetch('data', []).first
beta_attrs = {
  description: BETA_DESCRIPTION,
  feedbackEmail: BETA_FEEDBACK_EMAIL,
  privacyPolicyUrl: PRIVACY_POLICY_URL
}
if beta_localization
  puts "Setting TestFlight beta app description for #{attributes(beta_localization)['locale'] || LOCALE}."
  request(:patch, "/v1/betaAppLocalizations/#{beta_localization.fetch('id')}", body: {
    data: {
      type: 'betaAppLocalizations',
      id: beta_localization.fetch('id'),
      attributes: beta_attrs
    }
  })
else
  puts "Creating TestFlight beta app localization #{LOCALE}."
  request(:post, '/v1/betaAppLocalizations', body: {
    data: {
      type: 'betaAppLocalizations',
      attributes: beta_attrs.merge(locale: LOCALE),
      relationships: {
        app: {
          data: { type: 'apps', id: app_id }
        }
      }
    }
  })
end

def sorted_builds_for(app_id)
  builds = request(:get, "/v1/apps/#{app_id}/builds", query: {
    'limit' => '200'
  })
  builds.fetch('data', []).sort_by do |build|
    Time.parse(attributes(build)['uploadedDate'].to_s) rescue Time.at(0)
  end.reverse
end

sorted_builds = sorted_builds_for(app_id)
target_build = nil
if present(TARGET_BUILD_VERSION)
  puts "Waiting for target build #{TARGET_BUILD_VERSION} to become VALID."
  24.times do |attempt|
    sorted_builds = sorted_builds_for(app_id)
    target_build = sorted_builds.find { |build| attributes(build)['version'].to_s == TARGET_BUILD_VERSION }
    target_attrs = target_build ? attributes(target_build) : {}
    target_state = target_attrs['processingState'].to_s.upcase
    target_compliance = target_attrs['usesNonExemptEncryption']

    if target_build && target_compliance.nil?
      puts "Setting export compliance on target build #{TARGET_BUILD_VERSION}: usesNonExemptEncryption=#{USES_NON_EXEMPT_ENCRYPTION}."
      request(:patch, "/v1/builds/#{target_build.fetch('id')}", body: {
        data: {
          type: 'builds',
          id: target_build.fetch('id'),
          attributes: {
            usesNonExemptEncryption: USES_NON_EXEMPT_ENCRYPTION
          }
        }
      })
      target_attrs['usesNonExemptEncryption'] = USES_NON_EXEMPT_ENCRYPTION
    end

    break if target_build && target_state == 'VALID'

    puts "Target build #{TARGET_BUILD_VERSION} not ready yet (attempt #{attempt + 1}/24, state=#{target_state.empty? ? 'missing' : target_state})."
    sleep 30
  end
end

puts 'Recent builds:'
sorted_builds.take(8).each do |build|
  attrs = attributes(build)
  summary = attrs.slice(
    'version',
    'uploadedDate',
    'expired',
    'processingState',
    'usesNonExemptEncryption',
    'betaReviewState',
    'externalBuildState',
    'internalBuildState'
  )
  puts "- #{JSON.generate(summary)}"
end

latest_valid_build = if target_build && attributes(target_build)['processingState'].to_s.upcase == 'VALID'
                       target_build
                     else
                       sorted_builds.find do |build|
                         attrs = attributes(build)
                         !attrs['expired'] && attrs['processingState'].to_s.upcase == 'VALID'
                       end
                     end
if latest_valid_build
  battrs = attributes(latest_valid_build)
  puts "Latest valid build: #{battrs['version']} uploaded #{battrs['uploadedDate']}"
else
  puts 'No VALID TestFlight build found yet. Public link can be enabled only after a compatible build is processed/approved.'
end

groups = request(:get, "/v1/apps/#{app_id}/betaGroups", query: {
  'fields[betaGroups]' => 'name,isInternalGroup,hasAccessToAllBuilds,publicLinkEnabled,publicLinkId,publicLinkLimitEnabled,publicLinkLimit,publicLink,feedbackEnabled',
  'limit' => '200'
})
external_groups = groups.fetch('data', []).reject { |group| attributes(group)['isInternalGroup'] }
group = external_groups.find { |candidate| attributes(candidate)['name'] == GROUP_NAME }

unless group
  body = {
    data: {
      type: 'betaGroups',
      attributes: {
        name: GROUP_NAME,
        isInternalGroup: false,
        hasAccessToAllBuilds: false,
        publicLinkEnabled: true,
        publicLinkLimitEnabled: false,
        feedbackEnabled: true
      },
      relationships: {
        app: {
          data: { type: 'apps', id: app_id }
        }
      }
    }
  }
  puts "Creating external beta group: #{GROUP_NAME}"
  group = request(:post, '/v1/betaGroups', body: body).fetch('data')
end

group_id = group.fetch('id')
puts "Beta group: #{attributes(group)['name']} (#{group_id})"

puts 'Recent build beta details:'
sorted_builds.take(5).each do |build|
  attrs = attributes(build)
  code, detail_response = request_optional(:get, "/v1/builds/#{build.fetch('id')}/buildBetaDetail", query: {
    'fields[buildBetaDetails]' => 'autoNotifyEnabled,internalBuildState,externalBuildState'
  })
  if code.between?(200, 299) && detail_response && detail_response['data']
    detail_attrs = attributes(detail_response.fetch('data'))
    puts "- build #{attrs['version']}: #{JSON.generate(detail_attrs)}"
  else
    puts "- build #{attrs['version']}: buildBetaDetail unavailable HTTP #{code}"
  end
end

puts 'Public beta group builds:'
group_builds = request(:get, "/v1/betaGroups/#{group_id}/builds", query: {
  'fields[builds]' => 'version,uploadedDate,expired,processingState,usesNonExemptEncryption',
  'limit' => '20'
})
group_builds.fetch('data', []).sort_by do |build|
  Time.parse(attributes(build)['uploadedDate'].to_s) rescue Time.at(0)
end.reverse.each do |build|
  attrs = attributes(build)
  puts "- #{JSON.generate(attrs.slice('version', 'uploadedDate', 'expired', 'processingState', 'usesNonExemptEncryption'))}"
end

def build_beta_detail(build_id)
  code, response = request_optional(:get, "/v1/builds/#{build_id}/buildBetaDetail", query: {
    'fields[buildBetaDetails]' => 'autoNotifyEnabled,internalBuildState,externalBuildState'
  })
  return nil unless code.between?(200, 299) && response && response['data']

  attributes(response.fetch('data'))
end

def beta_review_submission(build_id)
  code, response = request_optional(:get, "/v1/builds/#{build_id}/betaAppReviewSubmission", query: {
    'fields[betaAppReviewSubmissions]' => 'betaReviewState,submittedDate'
  })
  return [code, nil] unless code.between?(200, 299) && response && response['data']

  [code, attributes(response.fetch('data'))]
end

if latest_valid_build
  latest_attrs = attributes(latest_valid_build)
  if latest_attrs['usesNonExemptEncryption'].nil?
    puts "Setting export compliance on build #{latest_attrs['version']}: usesNonExemptEncryption=#{USES_NON_EXEMPT_ENCRYPTION}."
    request(:patch, "/v1/builds/#{latest_valid_build.fetch('id')}", body: {
      data: {
        type: 'builds',
        id: latest_valid_build.fetch('id'),
        attributes: {
          usesNonExemptEncryption: USES_NON_EXEMPT_ENCRYPTION
        }
      }
    })
    latest_attrs['usesNonExemptEncryption'] = USES_NON_EXEMPT_ENCRYPTION
  end
  latest_detail = build_beta_detail(latest_valid_build.fetch('id'))
  puts "Latest valid beta detail: #{JSON.generate(latest_detail || {})}"
  submission_code, submission_attrs = beta_review_submission(latest_valid_build.fetch('id'))
  if submission_attrs
    puts "Latest valid beta review submission: #{JSON.generate(submission_attrs)}"
  else
    puts "Latest valid beta review submission unavailable HTTP #{submission_code}"
  end

  if latest_detail && latest_detail['externalBuildState'].to_s == 'READY_FOR_BETA_SUBMISSION' && submission_attrs.nil?
    puts "Submitting build #{latest_attrs['version']} for Beta App Review."
    submit_body = {
      data: {
        type: 'betaAppReviewSubmissions',
        relationships: {
          build: {
            data: { type: 'builds', id: latest_valid_build.fetch('id') }
          }
        }
      }
    }
    submit_code, submit_response = request_optional(:post, '/v1/betaAppReviewSubmissions', body: submit_body)
    if submit_code.between?(200, 299) && submit_response && submit_response['data']
      puts "Beta App Review submission created: #{JSON.generate(attributes(submit_response.fetch('data')))}"
    else
      warn "Beta App Review submission failed with HTTP #{submit_code}"
      warn JSON.pretty_generate(submit_response)
    end
  end
end

if latest_valid_build
  puts 'Adding latest valid build to beta group if not already attached.'
  code, response = request_optional(:post, "/v1/betaGroups/#{group_id}/relationships/builds", body: {
    data: [{ type: 'builds', id: latest_valid_build.fetch('id') }]
  })
  unless code.between?(200, 299) || code == 409
    warn "Could not attach the build to the external group. HTTP #{code}"
    warn JSON.pretty_generate(response)
    warn 'This usually means Beta App Review, export compliance, or TestFlight test information is still pending in App Store Connect.'
  end
end

patch_body = {
  data: {
    type: 'betaGroups',
    id: group_id,
    attributes: {
      publicLinkEnabled: true,
      publicLinkLimitEnabled: false,
      feedbackEnabled: true
    }
  }
}
puts 'Ensuring public link is enabled and open to anyone.'
request(:patch, "/v1/betaGroups/#{group_id}", body: patch_body)

fresh = request(:get, "/v1/betaGroups/#{group_id}", query: {
  'fields[betaGroups]' => 'name,isInternalGroup,publicLinkEnabled,publicLinkId,publicLinkLimitEnabled,publicLinkLimit,publicLink,feedbackEnabled'
}).fetch('data')
fattrs = attributes(fresh)
link = fattrs['publicLink'].to_s.strip

puts "Public link enabled: #{fattrs['publicLinkEnabled']}"
puts "Public link limit enabled: #{fattrs['publicLinkLimitEnabled']}"

if link.empty?
  warn 'No public TestFlight link was returned by App Store Connect yet.'
  warn 'Most likely blocker: the external TestFlight build still needs Beta App Review approval, export compliance, or TestFlight test information.'
  exit 2
end

puts "TESTFLIGHT_PUBLIC_LINK=#{link}"
