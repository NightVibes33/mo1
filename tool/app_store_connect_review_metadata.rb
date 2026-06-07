#!/usr/bin/env ruby
# frozen_string_literal: true

require 'base64'
require 'digest'
require 'json'
require 'net/http'
require 'openssl'
require 'time'
require 'uri'

API_HOST = 'api.appstoreconnect.apple.com'
BUNDLE_ID = ENV.fetch('DOPI_APP_BUNDLE_ID', 'app.mo1.player.39A8Q3T3TR')
LOCALE = ENV.fetch('DOPI_APP_LOCALE', 'en-US')
PRIMARY_CATEGORY_ID = ENV.fetch('DOPI_PRIMARY_CATEGORY_ID', 'MUSIC')
PRIVACY_POLICY_URL = ENV.fetch('DOPI_PRIVACY_POLICY_URL', 'https://github.com/NightVibes33/mo1/blob/main/privacy-policy.md')
COPYRIGHT_TEXT = ENV.fetch('DOPI_COPYRIGHT', '2026 NightVibes33')
CONTENT_RIGHTS_DECLARATION = ENV.fetch('DOPI_CONTENT_RIGHTS_DECLARATION', 'DOES_NOT_USE_THIRD_PARTY_CONTENT')
APP_DESCRIPTION = ENV.fetch(
  'DOPI_APP_DESCRIPTION',
  'døPi is a retro music player for iPhone and iPad inspired by classic pocket music players. Import MP3 files, connect Apple Music, browse albums with Cover Flow, view lyrics, tune playback with an equalizer, and use smooth song transitions in a focused player built for music fans.'
)
APP_KEYWORDS = ENV.fetch('DOPI_APP_KEYWORDS', 'music player,mp3,apple music,ipod,cover flow,lyrics,equalizer')
SUPPORT_URL = ENV.fetch('DOPI_SUPPORT_URL', 'https://github.com/NightVibes33/mo1')
USES_NON_EXEMPT_ENCRYPTION = ENV.fetch('DOPI_USES_NON_EXEMPT_ENCRYPTION', 'false').casecmp('true').zero?
SCREENSHOT_ROOT = ENV.fetch('DOPI_SCREENSHOT_ROOT', 'app_store/screenshots/exports')

KEY_ID = ENV.fetch('APP_STORE_CONNECT_KEY_ID')
ISSUER_ID = ENV.fetch('APP_STORE_CONNECT_ISSUER_ID')
PRIVATE_KEY = ENV.fetch('APP_STORE_CONNECT_API_KEY_P8')

SCREENSHOT_SETS = {
  'APP_IPHONE_65' => File.join(SCREENSHOT_ROOT, 'iphone-6.5'),
  'APP_IPAD_PRO_3GEN_129' => File.join(SCREENSHOT_ROOT, 'ipad-13')
}.freeze

if PRIVATE_KEY.strip.empty? || KEY_ID.strip.empty? || ISSUER_ID.strip.empty?
  warn 'Missing App Store Connect API key env.'
  exit 1
end

unless File.directory?(SCREENSHOT_ROOT)
  warn "Screenshot root not found: #{SCREENSHOT_ROOT}"
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

def upload_operation(operation, bytes)
  uri = URI(operation.fetch('url'))
  method = operation.fetch('method').to_s.upcase
  request_class = case method
                  when 'PUT' then Net::HTTP::Put
                  when 'POST' then Net::HTTP::Post
                  else raise "Unsupported upload operation method #{method}"
                  end

  offset = operation['offset'].to_i
  length = operation['length'].to_i
  body = bytes.byteslice(offset, length)

  request = request_class.new(uri)
  Array(operation['requestHeaders']).each do |header|
    request[header.fetch('name')] = header.fetch('value')
  end
  request.body = body

  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
    response = http.request(request)
    unless response.code.to_i.between?(200, 299)
      warn "Upload operation failed with HTTP #{response.code}"
      warn response.body
      exit 1
    end
  end
end

def screenshot_files(dir)
  Dir.glob(File.join(dir, '*.{png,jpg,jpeg}')).sort
end

app_response = api_request(:get, '/v1/apps', query: {
  'filter[bundleId]' => BUNDLE_ID,
  'fields[apps]' => 'name,bundleId,sku,primaryLocale',
  'limit' => '1'
})
app = app_response.fetch('data').first
unless app
  warn "No App Store Connect app found for bundle id #{BUNDLE_ID}."
  exit 1
end
app_id = app.fetch('id')
app_name = attributes(app)['name']
puts "App: #{app_name} (#{BUNDLE_ID}) id=#{app_id}"

puts "Setting content rights declaration to #{CONTENT_RIGHTS_DECLARATION}."
api_request(:patch, "/v1/apps/#{app_id}", body: {
  data: {
    type: 'apps',
    id: app_id,
    attributes: {
      contentRightsDeclaration: CONTENT_RIGHTS_DECLARATION
    }
  }
})

info_response = api_request(:get, "/v1/apps/#{app_id}/appInfos", query: {
  'include' => 'appInfoLocalizations,primaryCategory',
  'fields[appInfos]' => 'appStoreState,state,appInfoLocalizations,primaryCategory',
  'fields[appInfoLocalizations]' => 'locale,name,subtitle,privacyPolicyUrl,privacyChoicesUrl,privacyPolicyText',
  'limit' => '20'
})
app_info = info_response.fetch('data').first
unless app_info
  warn 'No App Info record found.'
  exit 1
end
app_info_id = app_info.fetch('id')

puts "Setting primary category to #{PRIMARY_CATEGORY_ID}."
api_request(:patch, "/v1/appInfos/#{app_info_id}", body: {
  data: {
    type: 'appInfos',
    id: app_info_id,
    relationships: {
      primaryCategory: {
        data: { type: 'appCategories', id: PRIMARY_CATEGORY_ID }
      }
    }
  }
})

app_info_localization = included(info_response, 'appInfoLocalizations').find do |item|
  attributes(item)['locale'] == LOCALE
end || included(info_response, 'appInfoLocalizations').first

if app_info_localization
  app_info_loc_id = app_info_localization.fetch('id')
  puts "Setting privacy policy URL on app info localization #{attributes(app_info_localization)['locale'] || LOCALE}."
  api_request(:patch, "/v1/appInfoLocalizations/#{app_info_loc_id}", body: {
    data: {
      type: 'appInfoLocalizations',
      id: app_info_loc_id,
      attributes: {
        privacyPolicyUrl: PRIVACY_POLICY_URL
      }
    }
  })
else
  puts "Creating app info localization #{LOCALE} with privacy policy URL."
  api_request(:post, '/v1/appInfoLocalizations', body: {
    data: {
      type: 'appInfoLocalizations',
      attributes: {
        locale: LOCALE,
        name: app_name,
        privacyPolicyUrl: PRIVACY_POLICY_URL
      },
      relationships: {
        appInfo: { data: { type: 'appInfos', id: app_info_id } }
      }
    }
  })
end

versions_response = api_request(:get, "/v1/apps/#{app_id}/appStoreVersions", query: {
  'filter[platform]' => 'IOS',
  'include' => 'appStoreVersionLocalizations,build',
  'fields[appStoreVersions]' => 'platform,versionString,appStoreState,appVersionState,copyright,createdDate,appStoreVersionLocalizations,build',
  'fields[appStoreVersionLocalizations]' => 'locale,description,keywords,marketingUrl,promotionalText,supportUrl,whatsNew,appScreenshotSets',
  'fields[builds]' => 'version,uploadedDate,processingState,expired,usesNonExemptEncryption',
  'limit' => '50'
})
versions = versions_response.fetch('data')
editable_states = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED WAITING_FOR_REVIEW INVALID_BINARY]
version = versions.find do |candidate|
  attrs = attributes(candidate)
  editable_states.include?(attrs['appStoreState'].to_s) || editable_states.include?(attrs['appVersionState'].to_s)
end || versions.first
unless version
  warn 'No iOS App Store version found.'
  exit 1
end
version_id = version.fetch('id')
version_attrs = attributes(version)
puts "Using App Store version #{version_attrs['versionString']} state=#{version_attrs['appStoreState'] || version_attrs['appVersionState']} id=#{version_id}."

build_id = version.dig('relationships', 'build', 'data', 'id')
build = included(versions_response, 'builds').find { |item| item['id'] == build_id } || included(versions_response, 'builds').first
unless build
  build_response = api_request(:get, "/v1/appStoreVersions/#{version_id}/build", query: {
    'fields[builds]' => 'version,uploadedDate,processingState,expired,usesNonExemptEncryption'
  }, allow: [404])
  build = build_response['data']
end
if build
  build_id = build.fetch('id')
  build_version = attributes(build)['version']
  puts "Setting export compliance on build #{build_version || build_id}: usesNonExemptEncryption=#{USES_NON_EXEMPT_ENCRYPTION}."
  api_request(:patch, "/v1/builds/#{build_id}", body: {
    data: {
      type: 'builds',
      id: build_id,
      attributes: {
        usesNonExemptEncryption: USES_NON_EXEMPT_ENCRYPTION
      }
    }
  })
else
  warn 'No build is attached to this App Store version; cannot set export compliance.'
end

puts "Setting copyright to #{COPYRIGHT_TEXT}."
api_request(:patch, "/v1/appStoreVersions/#{version_id}", body: {
  data: {
    type: 'appStoreVersions',
    id: version_id,
    attributes: {
      copyright: COPYRIGHT_TEXT
    }
  }
})

localization = included(versions_response, 'appStoreVersionLocalizations').find do |item|
  attributes(item)['locale'] == LOCALE
end || included(versions_response, 'appStoreVersionLocalizations').first
unless localization
  warn 'No App Store version localization found. Create the English localization in App Store Connect, then rerun.'
  exit 1
end
localization_id = localization.fetch('id')
puts "Using version localization #{attributes(localization)['locale'] || LOCALE} id=#{localization_id}."

puts 'Setting English description, keywords, and support URL.'
api_request(:patch, "/v1/appStoreVersionLocalizations/#{localization_id}", body: {
  data: {
    type: 'appStoreVersionLocalizations',
    id: localization_id,
    attributes: {
      description: APP_DESCRIPTION,
      keywords: APP_KEYWORDS,
      supportUrl: SUPPORT_URL
    }
  }
})

sets_response = api_request(:get, "/v1/appStoreVersionLocalizations/#{localization_id}/appScreenshotSets", query: {
  'fields[appScreenshotSets]' => 'screenshotDisplayType,appScreenshots',
  'include' => 'appScreenshots',
  'fields[appScreenshots]' => 'fileName,fileSize,sourceFileChecksum,assetDeliveryState',
  'limit' => '50',
  'limit[appScreenshots]' => '50'
})
existing_sets = sets_response.fetch('data')
existing_screenshots = included(sets_response, 'appScreenshots')

SCREENSHOT_SETS.each do |display_type, dir|
  files = screenshot_files(dir)
  if files.empty?
    warn "No screenshots found for #{display_type} in #{dir}."
    exit 1
  end

  set = existing_sets.find { |item| attributes(item)['screenshotDisplayType'] == display_type }
  unless set
    puts "Creating screenshot set #{display_type}."
    set = api_request(:post, '/v1/appScreenshotSets', body: {
      data: {
        type: 'appScreenshotSets',
        attributes: { screenshotDisplayType: display_type },
        relationships: {
          appStoreVersionLocalization: {
            data: { type: 'appStoreVersionLocalizations', id: localization_id }
          }
        }
      }
    }).fetch('data')
  end
  set_id = set.fetch('id')

  related_ids = Array(set.dig('relationships', 'appScreenshots', 'data')).map { |item| item['id'] }
  if related_ids.empty?
    related_ids = existing_screenshots.select do |shot|
      shot.dig('relationships', 'appScreenshotSet', 'data', 'id') == set_id
    end.map { |shot| shot.fetch('id') }
  end
  related_ids.each do |screenshot_id|
    puts "Deleting existing #{display_type} screenshot #{screenshot_id}."
    api_request(:delete, "/v1/appScreenshots/#{screenshot_id}", allow: [404])
  end

  files.each_with_index do |path, index|
    bytes = File.binread(path)
    file_name = format('%02d-%s', index + 1, File.basename(path))
    checksum = Digest::MD5.hexdigest(bytes)
    puts "Uploading #{display_type} #{file_name} (#{bytes.bytesize} bytes)."

    reservation = api_request(:post, '/v1/appScreenshots', body: {
      data: {
        type: 'appScreenshots',
        attributes: {
          fileSize: bytes.bytesize,
          fileName: file_name
        },
        relationships: {
          appScreenshotSet: {
            data: { type: 'appScreenshotSets', id: set_id }
          }
        }
      }
    }).fetch('data')

    screenshot_id = reservation.fetch('id')
    attributes(reservation).fetch('uploadOperations').each do |operation|
      upload_operation(operation, bytes)
    end

    api_request(:patch, "/v1/appScreenshots/#{screenshot_id}", body: {
      data: {
        type: 'appScreenshots',
        id: screenshot_id,
        attributes: {
          uploaded: true,
          sourceFileChecksum: checksum
        }
      }
    })
  end
end

puts 'DONE App Store metadata and screenshots update.'
