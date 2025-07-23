# frozen_string_literal: true

require_relative 'base'
require_relative '../utils'

module ZCA
  module API
    class Login < Base
      def login(encrypt_params: true)
        encrypted_params = get_encrypt_param('getlogininfo', encrypt_params)
        url = Utils.make_url(context, 'https://wpa.chat.zalo.me/api/login/getLoginInfo', encrypted_params[:params].merge(nretry: 0))
        resp = request(url, {}, response_type: :json)
        puts "[DEBUG] login API resp: #{resp.inspect}"
        if encrypted_params[:enk]
          decrypted = Utils.decrypt_resp(encrypted_params[:enk], resp['data'])
          puts "[DEBUG] decrypted: #{decrypted.inspect}"
          begin
            parsed = JSON.parse(decrypted)
            return parsed if parsed.is_a?(Hash)
          rescue
          end
          return nil
        end
        resp
      rescue => e
        Utils.logger(context).error('Login failed:', e)
        raise e
      end

      def get_server_info(encrypt_params: true)
        encrypted_params = get_encrypt_param('getserverinfo', encrypt_params)
        url = Utils.make_url(context, 'https://wpa.chat.zalo.me/api/login/getServerInfo', {
          imei: context.imei,
          type: context.API_TYPE,
          client_version: context.API_VERSION,
          computer_name: 'Web',
          signkey: encrypted_params[:params][:signkey],
        })
        resp = request(url, {}, response_type: :json)
        raise ZCA::Errors::ZaloApiError.new("Failed to fetch server info: #{resp['error_message']}") if resp['data'].nil?
        resp['data']
      end

      private

      def get_encrypt_param(type, encrypt_params)
        params = {}
        data = {
          computer_name: 'Web',
          imei: context.imei,
          language: context.language,
          ts: Time.now.to_i * 1000,
        }
        encrypted_data = _encrypt_param(data, encrypt_params)
        if encrypted_data.nil?
          params.merge!(data)
        else
          params.merge!(encrypted_data[:encrypted_params])
          params[:params] = encrypted_data[:encrypted_data]
        end
        params[:type] = context.API_TYPE
        params[:client_version] = context.API_VERSION
        params[:signkey] = if type == 'getserverinfo'
          Utils.get_sign_key(type, {
            imei: context.imei,
            type: context.API_TYPE,
            client_version: context.API_VERSION,
            computer_name: 'Web',
          })
        else
          Utils.get_sign_key(type, params)
        end
        {
          params: params,
          enk: encrypted_data ? encrypted_data[:enk] : nil
        }
      end

      def _encrypt_param(data, encrypt_params)
        return nil unless encrypt_params
        encryptor = Utils::ParamsEncryptor.new(type: context.API_TYPE, imei: data[:imei], first_launch_time: Time.now.to_i * 1000)
        begin
          stringified = data.to_json
          encrypted_key = encryptor.get_encrypt_key
          encoded_data = Utils::ParamsEncryptor.encode_aes(encrypted_key, stringified, :base64, false)
          params = encryptor.get_params
          params ? {
            encrypted_data: encoded_data,
            encrypted_params: params,
            enk: encrypted_key
          } : nil
        rescue => e
          raise ZCA::Errors::ZaloApiError.new("Failed to encrypt params: #{e}")
        end
      end
    end
  end
end 