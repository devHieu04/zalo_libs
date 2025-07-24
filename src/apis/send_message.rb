# frozen_string_literal: true

require_relative '../utils'
require_relative '../models/send_message'
require_relative '../models/attachment'
require 'json'
require 'uri'
require 'base64'
require 'openssl'
require_relative 'upload_attachment'

module ZCA
  module API
    class SendMessage
      include ZCA::Models

      def initialize(context)
        @context = context
      end

      # Gửi tin nhắn tới user hoặc group
      # message: MessageContent hoặc String
      # thread_id: id user hoặc group
      # type: :user hoặc :group
      def send_message(message, thread_id, type = :user)
        raise ZCA::Errors::ZaloApiError.new('Missing message content') if message.nil? || (message.respond_to?(:empty?) && message.empty?)
        raise ZCA::Errors::ZaloApiError.new('Missing thread_id') if thread_id.nil? || thread_id.empty?
        message = MessageContent.new(msg: message) if message.is_a?(String)
        msg = message.msg || ''
        quote = message.quote
        attachments = message.attachments
        mentions = message.mentions
        ttl = message.ttl
        styles = message.styles
        urgency = message.urgency
        responses = { message: nil, attachment: [] }

        # Xử lý gửi file/attachment
        if attachments && !attachments.empty?
          uploader = ZCA::API::UploadAttachment.new(@context)
          upload_results = uploader.upload_attachment(attachments, thread_id, type)
          responses[:attachment] = upload_results
          # Nếu là ảnh đơn (jpg/png/webp) và không có quote, có thể gửi desc cùng file, không cần gửi text riêng
          first_ext = ZCA::Utils.get_file_extension(attachments.is_a?(Array) ? attachments[0] : attachments).downcase
          is_single_image = attachments.is_a?(Array) ? attachments.size == 1 && %w[jpg jpeg png webp].include?(first_ext) : %w[jpg jpeg png webp].include?(first_ext)
          can_be_desc = is_single_image && (!quote)
          # Nếu không phải ảnh đơn hoặc có quote, gửi message text riêng
          if (!can_be_desc && msg.length > 0) || (msg.length > 0 && quote)
            params = build_message_params(message, thread_id, type)
            encrypted_params = ZCA::Utils.encode_aes(@context.secret_key, params.to_json)
            url = build_service_url(type, thread_id, quote, @context)
            url = append_query(url, 'params', encrypted_params)
            resp = ZCA::Utils.request(@context, url, { method: :post }, :json)
            if resp.is_a?(String)
              resp = JSON.parse(resp)
            end
            if resp['error_code'] != 0
              raise ZCA::Errors::ZaloApiError.new(resp['error_message'], resp['error_code'])
            end
            if resp['data']
              decoded = ZCA::Utils.decode_zalo_response(@context.secret_key, resp['data'])
              responses[:message] = decoded['data'] if decoded.is_a?(Hash) && decoded['data']
            end
            msg = ''
            mentions = nil
          end
        end

        # Xử lý gửi tin nhắn văn bản nếu còn msg
        if msg && !msg.empty?
          params = build_message_params(message, thread_id, type)
          encrypted_params = ZCA::Utils.encode_aes(@context.secret_key, params.to_json)
          url = build_service_url(type, thread_id, quote, @context)
          url = append_query(url, 'params', encrypted_params)
          resp = ZCA::Utils.request(@context, url, { method: :post }, :json)
          if resp.is_a?(String)
            resp = JSON.parse(resp)
          end
          if resp['error_code'] != 0
            raise ZCA::Errors::ZaloApiError.new(resp['error_message'], resp['error_code'])
          end
          if resp['data']
            decoded = ZCA::Utils.decode_zalo_response(@context.secret_key, resp['data'])
            responses[:message] = decoded['data'] if decoded.is_a?(Hash) && decoded['data']
          end
        end
        responses
      end

      private

      def build_message_params(message, thread_id, type)
        is_group = (type.to_s == 'group')
        params = {
          message: message.msg,
          clientId: (Time.now.to_f * 1000).to_i,
          mentionInfo: build_mentions(message.mentions, type),
          imei: is_group ? nil : @context.imei,
          ttl: message.ttl || 0,
          visibility: is_group ? 0 : nil,
          toid: is_group ? nil : thread_id,
          grid: is_group ? thread_id : nil
        }
        params.delete_if { |_, v| v.nil? }
        # Styles
        if message.styles && !message.styles.empty?
          params[:textProperties] = {
            styles: message.styles.map { |s| s.to_h },
            ver: 0
          }.to_json
        end
        # Urgency
        if message.urgency && message.urgency != Models::Urgency::DEFAULT
          params[:metaData] = { urgency: message.urgency }
        end
        # Quote
        if message.quote
          params[:qmsgOwner] = message.quote.uid_from
          params[:qmsgId] = message.quote.msg_id
          params[:qmsgCliId] = message.quote.cli_msg_id
          params[:qmsgType] = message.quote.msg_type
          params[:qmsgTs] = message.quote.ts
          params[:qmsg] = message.quote.content.is_a?(String) ? message.quote.content : ''
          params[:qmsgTTL] = message.quote.ttl
        end
        params
      end

      def build_mentions(mentions, type)
        return nil unless mentions && !mentions.empty? && type.to_s == 'group'
        mentions_final = mentions.map do |m|
          { pos: m.pos, uid: m.uid, len: m.len, type: (m.uid == '-1' ? 1 : 0) }
        end
        mentions_final.to_json
      end

      def build_service_url(type, thread_id, quote, ctx)
        base_url = if type.to_s == 'group'
          ctx.zpw_service_map['group'][0] + '/api/group'
        else
          ctx.zpw_service_map['chat'][0] + '/api/message'
        end
        # Xử lý path cho quote/mention/sendmsg/sms
        uri = URI(base_url)
        if quote
          uri.path += '/quote'
        else
          uri.path += if type.to_s == 'group'
            '/sendmsg'
          else
            '/sms'
          end
        end
        uri.to_s
      end

      def append_query(url, key, value)
        uri = URI(url)
        q = URI.decode_www_form(uri.query || '')
        q << [key, value]
        uri.query = URI.encode_www_form(q)
        uri.to_s
      end
    end
  end
end