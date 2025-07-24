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
        secret_key = context.secret_key || context.secretKey
        raise ZCA::Errors::ZaloApiError.new('Missing secret_key in context') unless secret_key
        decoded_key = Base64.decode64(secret_key)
        encrypted_params = ZCA::Utils.encode_aes(secret_key, params.to_json)

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
        # Bổ sung zpw_type vào URL (giống JS)
        zpw_type = context.respond_to?(:api_type) && context.api_type ? context.api_type : 30
        if url.include?("?")
          url += "&zpw_type=#{zpw_type}"
        else
          url += "?zpw_type=#{zpw_type}"
        end
        # Bổ sung zpw_ver vào URL (giống JS)
        zpw_ver = context.respond_to?(:api_version) && context.api_version ? context.api_version : 663
        if url.include?("?")
          url += "&zpw_ver=#{zpw_ver}"
        else
          url += "?zpw_ver=#{zpw_ver}"
        end
        headers = {
          'accept' => 'application/json, text/plain, */*',
          'content-type' => 'application/x-www-form-urlencoded',
          'user-agent' => context.userAgent || context.user_agent || 'Mozilla/5.0',
        }
        # Debug cookie header
        if context.respond_to?(:cookie) && context.cookie
          if context.cookie.is_a?(HTTP::CookieJar)
            context.cookie.cookies(URI(url)).map { |c| "#{c.name}=#{c.value}" }.join('; ')
          elsif context.cookie.is_a?(String)
            puts "[DEBUG] Cookie header: #{context.cookie}"
          elsif context.cookie.respond_to?(:to_cookie_string)
            puts "[DEBUG] Cookie header: #{context.cookie.to_cookie_string}"
          end
        end
        resp = Utils.request(context, url, { method: :get, headers: headers }, :json)
        parsed = JSON.parse(resp)
        if parsed['error_code'] != 0
          raise ZCA::Errors::ZaloApiError.new(parsed['error_message'], parsed['error_code'])
        end
        # Giải mã data nếu có (giống JS)
        if parsed['data']
          decoded = ZCA::Utils.decode_zalo_response(secret_key, parsed['data'])
          return decoded['data'] if decoded.is_a?(Hash) && decoded['data']
          return decoded
        end
        nil
      end
    end
  end
end
