# frozen_string_literal: true

require_relative '../context'
require_relative '../utils'
require_relative '../errors'

module ZCA
  module API
    class Base
      attr_reader :context

      def initialize(context)
        @context = context
      end

      # Chuẩn hóa gửi request, tự động dùng context, xử lý lỗi, decode, parse JSON
      def request(url, options = {}, response_type: :json, decode: nil)
        begin
          resp = Utils.request(context, url, options)
          data =
            case response_type
            when :json
              resp.is_a?(String) ? JSON.parse(resp) : resp
            when :text
              resp.is_a?(String) ? resp : resp.body
            else
              resp
            end
          # decode nếu cần (ví dụ: AES, base64, ...)
          data = decode.call(data) if decode && decode.respond_to?(:call)
          data
        rescue ZCA::Errors::ZaloApiError => e
          # Có thể log hoặc raise lại lỗi chuẩn hóa
          raise e
        rescue => e
          raise ZCA::Errors::ZaloApiError.new("API request error: #{e.message}")
        end
      end

      # Tiện ích: parse/decode response nếu cần
      def parse_response(data, decode: nil)
        decode && decode.respond_to?(:call) ? decode.call(data) : data
      end
    end
  end
end 