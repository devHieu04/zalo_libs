# frozen_string_literal: true

require_relative 'base'
require_relative '../models/enum'
require 'json'
require 'pry'
require 'base64'

module ZCA
  module API
    class FindUser < Base
      # Tìm user theo số điện thoại
      # Trả về hash thông tin user hoặc raise lỗi
      def find_user(phone_number)
        raise ZCA::Errors::ZaloApiError.new('Missing phone_number') if phone_number.nil? || phone_number.empty?
        language = context.language || 'vi'
        phone = phone_number.dup
        if phone.start_with?('0') && language == 'vi'
          phone = '84' + phone[1..-1]
        end
        params = {
          phone: phone,
          avatar_size: 240,
          language: language,
          imei: context.imei,
          reqSrc: 40
        }
        puts "[DEBUG] params: #{params.inspect}"
        secret_key = context.secret_key || context.secretKey
        raise ZCA::Errors::ZaloApiError.new('Missing secret_key in context') unless secret_key
        decoded_key = Base64.decode64(secret_key)
        puts "[DEBUG] secret_key: #{secret_key.inspect}"
        puts "[DEBUG] decoded_key.bytesize: #{decoded_key.bytesize}"
        encrypted_params = ZCA::Utils.encode_aes(secret_key, params.to_json)
        puts "[DEBUG] encrypted_params: #{encrypted_params.inspect}"

        # Lấy SERVICE_URL động từ context
        service_url =
          if context.respond_to?(:zpw_service_map) && context.zpw_service_map && context.zpw_service_map['friend']
            context.zpw_service_map['friend'][0]
          elsif context.respond_to?(:zpwServiceMap) && context.zpwServiceMap && context.zpwServiceMap['friend']
            context.zpwServiceMap['friend'][0]
          else
            'https://api-wpa.chat.zalo.me'
          end
        url = service_url + "/api/friend/profile/get?params=#{CGI.escape(encrypted_params)}"
        headers = {
          'accept' => 'application/json, text/plain, */*',
          'content-type' => 'application/x-www-form-urlencoded',
          'user-agent' => context.userAgent || context.user_agent || 'Mozilla/5.0',
        }
        # Debug cookie header
        if context.respond_to?(:cookie) && context.cookie
          if context.cookie.is_a?(HTTP::CookieJar)
            cookies = context.cookie.cookies(URI(url)).map { |c| "#{c.name}=#{c.value}" }.join('; ')
            puts "[DEBUG] Cookie header: #{cookies}"
          elsif context.cookie.is_a?(String)
            puts "[DEBUG] Cookie header: #{context.cookie}"
          elsif context.cookie.respond_to?(:to_cookie_string)
            puts "[DEBUG] Cookie header: #{context.cookie.to_cookie_string}"
          end
        end
        resp = Utils.request(context, url, { method: :get, headers: headers }, :json)
        if resp['error'] && resp['error']['code'] != 216
          raise ZCA::Errors::ZaloApiError.new(resp['error']['message'], resp['error']['code'])
        end
        resp['data']
      end
    end
  end
end 