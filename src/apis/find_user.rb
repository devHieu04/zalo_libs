# frozen_string_literal: true

require_relative 'base'
require_relative '../models/enum'
require 'json'

module ZCA
  module API
    class FindUser < Base
      SERVICE_URL = 'https://friend.zalo.me/api/friend/profile/get'

      # Tìm user theo số điện thoại
      # Trả về hash thông tin user hoặc raise lỗi
      def find_user(phone_number)
        raise ZCA::Errors::ZaloApiError.new('Missing phone_number') if phone_number.nil? || phone_number.empty?
        phone = phone_number.dup
        if phone.start_with?('0') && context.language == 'vi'
          phone = '84' + phone[1..-1]
        end
        params = {
          phone: phone,
          avatar_size: 240,
          language: context.language,
          imei: context.imei,
          reqSrc: 40
        }
        secret_key = context.secret_key || context.secretKey
        raise ZCA::Errors::ZaloApiError.new('Missing secret_key in context') unless secret_key
        encrypted_params = ZCA::Utils.encode_aes(secret_key, params.to_json)
        raise ZCA::Errors::ZaloApiError.new('Failed to encrypt message') unless encrypted_params
        url = SERVICE_URL + "?params=#{CGI.escape(encrypted_params)}"
        headers = {
          'accept' => 'application/json, text/plain, */*',
          'content-type' => 'application/x-www-form-urlencoded',
          'user-agent' => context.userAgent || context.user_agent || 'Mozilla/5.0',
        }
        resp = Utils.request(context, url, { method: :get, headers: headers }, :json)
        # Giải mã response nếu cần
        if resp['error'] && resp['error']['code'] != 216
          raise ZCA::Errors::ZaloApiError.new(resp['error']['message'], resp['error']['code'])
        end
        resp['data']
      end
    end
  end
end 