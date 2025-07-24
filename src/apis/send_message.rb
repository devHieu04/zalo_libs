# frozen_string_literal: true

require_relative 'base'
require_relative 'upload_attachment'
require_relative '../utils'
require_relative '../models/enum'
require_relative '../models/attachment'
require 'json'
require 'ostruct'

module ZCA
  module API
    module TextStyle
      BOLD = 'b'
      ITALIC = 'i'
      UNDERLINE = 'u'
      STRIKE_THROUGH = 's'
      RED = 'c_db342e'
      ORANGE = 'c_f27806'
      YELLOW = 'c_f7b503'
      GREEN = 'c_15a85f'
      SMALL = 'f_13'
      BIG = 'f_18'
      UNORDERED_LIST = 'lst_1'
      ORDERED_LIST = 'lst_2'
      INDENT = 'ind_$'
    end

    module Urgency
      DEFAULT = 0
      IMPORTANT = 1
      URGENT = 2
    end

    class SendMessage < Base
      ATTACHMENT_URL_TYPE = {
        'image' => 'photo_original/send?',
        'gif' => 'gif?',
        'video' => 'asyncfile/msg?',
        'others' => 'asyncfile/msg?'
      }.freeze

      def send_message(message, thread_id, type = ZCA::Models::ThreadType::USER)
        sharefile = context.settings&.features&.sharefile
        raise ZCA::Errors::ZaloApiError.new('Missing message content') if message.nil?
        raise ZCA::Errors::ZaloApiError.new('Missing thread_id') if thread_id.nil? || thread_id.to_s.empty?
        message = { msg: message } if message.is_a?(String)
        msg = message[:msg]
        quote = message[:quote]
        attachments = message[:attachments]
        mentions = message[:mentions]
        ttl = message[:ttl]
        styles = message[:styles]
        urgency = message[:urgency]
        attachments = [attachments] if attachments && !attachments.is_a?(Array)
        if (!msg || msg.empty?) && (!attachments || attachments.empty?)
          raise ZCA::Errors::ZaloApiError.new('Missing message content')
        end
        if attachments && attachments.size > sharefile.max_file
          raise ZCA::Errors::ZaloApiError.new("Exceed maximum file of #{sharefile.max_file}")
        end
        responses = { message: nil, attachment: [] }
        if attachments && !attachments.empty?
          first_ext = ZCA::Utils.get_file_extension(attachments[0].is_a?(String) ? attachments[0] : attachments[0].filename)
          is_single_file = attachments.size == 1
          can_be_desc = is_single_file && %w[jpg jpeg png webp].include?(first_ext)
          if ((!can_be_desc && msg && !msg.empty?) || (msg && !msg.empty? && quote))
            responses[:message] = handle_message(message, thread_id, type)
            msg = ''
            mentions = nil
          end
          responses[:attachment] = handle_attachment({ msg: msg, mentions: mentions, attachments: attachments, quote: quote, ttl: ttl, styles: styles, urgency: urgency }, thread_id, type)
          msg = ''
        end
        if msg && !msg.empty?
          responses[:message] = handle_message(message, thread_id, type)
        end
        responses
      end

      private

      def handle_message(message, thread_id, type)
        msg = message[:msg]
        styles = message[:styles]
        urgency = message[:urgency]
        mentions = message[:mentions]
        quote = message[:quote]
        ttl = message[:ttl]
        is_group = (type == ZCA::Models::ThreadType::GROUP)
        mentions_final, msg_final = handle_mentions(type, msg, mentions)
        msg = msg_final
        if quote
          if quote[:msg_type] == 'webchat'
            raise ZCA::Errors::ZaloApiError.new('This kind of `webchat` quote type is not available')
          end
          if quote[:msg_type] == 'group.poll'
            raise ZCA::Errors::ZaloApiError.new('The `group.poll` quote type is not available')
          end
        end
        is_mentions_valid = mentions_final.any? && is_group
        params = if quote
          {
            toid: is_group ? nil : thread_id,
            grid: is_group ? thread_id : nil,
            message: msg,
            clientId: (Time.now.to_f * 1000).to_i,
            mentionInfo: is_mentions_valid ? mentions_final.to_json : nil,
            qmsgOwner: quote[:uid_from],
            qmsgId: quote[:msg_id],
            qmsgCliId: quote[:cli_msg_id],
            qmsgType: ZCA::Utils.get_client_message_type(quote[:msg_type]),
            qmsgTs: quote[:ts],
            qmsg: quote[:content].is_a?(String) ? quote[:content] : prepare_qmsg(quote),
            imei: is_group ? nil : context.imei,
            visibility: is_group ? 0 : nil,
            qmsgAttach: is_group ? prepare_qmsg_attach(quote).to_json : nil,
            qmsgTTL: quote[:ttl],
            ttl: ttl || 0
          }
        else
          {
            message: msg,
            clientId: (Time.now.to_f * 1000).to_i,
            mentionInfo: is_mentions_valid ? mentions_final.to_json : nil,
            imei: is_group ? nil : context.imei,
            ttl: ttl || 0,
            visibility: is_group ? 0 : nil,
            toid: is_group ? nil : thread_id,
            grid: is_group ? thread_id : nil
          }
        end
        handle_styles(params, styles)
        handle_urgency(params, urgency)
        ZCA::Utils.remove_undefined_keys(params)
        encrypted_params = ZCA::Utils.encode_aes(context.secret_key, params.to_json)
        raise ZCA::Errors::ZaloApiError.new('Failed to encrypt message') unless encrypted_params
        service_url = get_service_url(type, quote, params)
        headers = {
          'Content-Type' => 'application/x-www-form-urlencoded',
          'User-Agent' => context.userAgent || context.user_agent || 'Mozilla/5.0',
          'Accept' => '*/*',
          'Accept-Language' => 'vi-VN,vi;q=0.9,fr-FR;q=0.8,fr;q=0.7,en-US;q=0.6,en;q=0.5',
          'Referer' => 'https://chat.zalo.me/'
        }
        body = URI.encode_www_form(params: encrypted_params)
        resp = ZCA::Utils.request(context, service_url, {
          method: :post,
          headers: headers,
          body: body
        })
        resp.is_a?(String) ? JSON.parse(resp) : resp
      end

      def handle_attachment(message, thread_id, type)
        attachments = message[:attachments]
        msg = message[:msg]
        mentions = message[:mentions]
        quote = message[:quote]
        ttl = message[:ttl]
        styles = message[:styles]
        urgency = message[:urgency]
        is_group = (type == ZCA::Models::ThreadType::GROUP)
        upload_api = ZCA::API::UploadAttachment.new(context)
        upload_attachments = upload_api.upload_attachment(attachments, thread_id, type)
        results = []
        upload_attachments.each do |attachment|
          params = build_attachment_params(attachment, msg, thread_id, is_group, ttl, urgency, mentions, quote, upload_attachments)
          ZCA::Utils.remove_undefined_keys(params)
          encrypted_params = ZCA::Utils.encode_aes(context.secret_key, params.to_json)
          raise ZCA::Errors::ZaloApiError.new('Failed to encrypt message') unless encrypted_params
          url = build_attachment_url(type, attachment[:fileType])
          headers = {
            'Content-Type' => 'application/x-www-form-urlencoded',
            'User-Agent' => context.userAgent || context.user_agent || 'Mozilla/5.0',
            'Accept' => '*/*',
            'Accept-Language' => 'vi-VN,vi;q=0.9,fr-FR;q=0.8,fr;q=0.7,en-US;q=0.6,en;q=0.5',
            'Referer' => 'https://chat.zalo.me/'
          }
          body = URI.encode_www_form(params: encrypted_params)
          resp = ZCA::Utils.request(context, url, {
            method: :post,
            headers: headers,
            body: body
          })
          results << (resp.is_a?(String) ? JSON.parse(resp) : resp)
        end
        results
      end

      def handle_mentions(type, msg, mentions)
        total_mention_len = 0
        mentions_final =
          if mentions.is_a?(Array) && type == ZCA::Models::ThreadType::GROUP
            mentions
              .select { |m| m[:pos] && m[:uid] && m[:len] && m[:pos] >= 0 && m[:len] > 0 }
              .map do |m|
                total_mention_len += m[:len]
                {
                  pos: m[:pos],
                  uid: m[:uid],
                  len: m[:len],
                  type: m[:uid] == '-1' ? 1 : 0
                }
              end
          else
            []
          end
        raise ZCA::Errors::ZaloApiError.new('Invalid mentions: total mention characters exceed message length') if total_mention_len > (msg&.length || 0)
        [mentions_final, msg]
      end

      def handle_styles(params, styles)
        return unless styles
        params[:textProperties] = {
          styles: styles.map do |e|
            style_final = e.dup
            style_final[:indentSize] = nil
            style_final[:st] = (e[:st] == TextStyle::INDENT ? TextStyle::INDENT.gsub('$', "#{e[:indentSize] || 1}0") : e[:st])
            style_final.compact
          end,
          ver: 0
        }.to_json
      end

      def handle_urgency(params, urgency)
        if urgency == Urgency::IMPORTANT || urgency == Urgency::URGENT
          params[:metaData] = { urgency: urgency }
        end
      end

      def prepare_qmsg_attach(quote)
        quote_data = quote
        return quote_data[:property_ext] if quote_data[:content].is_a?(String)
        if quote_data[:msg_type] == 'chat.todo'
          {
            properties: {
              color: 0, size: 0, type: 0, subType: 0, ext: '{"shouldParseLinkOrContact":0}'
            }
          }
        else
          content = quote_data[:content]
          {
            **content,
            thumbUrl: content[:thumb],
            oriUrl: content[:href],
            normalUrl: content[:href]
          }
        end
      end

      def prepare_qmsg(quote)
        quote_data = quote
        if quote_data[:msg_type] == 'chat.todo' && !quote_data[:content].is_a?(String)
          JSON.parse(quote_data[:content][:params])['item']['content']
        else
          ''
        end
      end

      def get_service_url(type, quote, params)
        service_map = context.zpw_service_map
        base_url = if type == ZCA::Models::ThreadType::GROUP
          ZCA::Utils.make_url(context, service_map['group'][0] + '/api/group', { nretry: 0 })
        else
          ZCA::Utils.make_url(context, service_map['chat'][0] + '/api/message', { nretry: 0 })
        end
        uri = URI(base_url)
        if quote
          uri.path += '/quote'
        else
          uri.path += if type == ZCA::Models::ThreadType::GROUP
            params[:mentionInfo] ? '/mention' : '/sendmsg'
          else
            '/sms'
          end
        end
        uri.to_s
      end

      def build_attachment_params(attachment, msg, thread_id, is_group, ttl, urgency, mentions, quote, upload_attachments)
        case attachment[:fileType]
        when 'image'
          {
            photoId: attachment[:photoId],
            clientId: attachment[:clientFileId],
            desc: msg,
            width: attachment[:width],
            height: attachment[:height],
            toid: is_group ? nil : thread_id.to_s,
            grid: is_group ? thread_id.to_s : nil,
            rawUrl: attachment[:normalUrl],
            hdUrl: attachment[:hdUrl],
            thumbUrl: attachment[:thumbUrl],
            oriUrl: is_group ? attachment[:normalUrl] : nil,
            normalUrl: is_group ? nil : attachment[:normalUrl],
            hdSize: attachment[:totalSize].to_s,
            zsource: -1,
            ttl: ttl || 0,
            jcp: '{"convertible":"jxl"}',
            groupLayoutId: upload_attachments.size > 1 ? Time.now.to_i : nil,
            isGroupLayout: upload_attachments.size > 1 ? 1 : nil,
            idInGroup: upload_attachments.size > 1 ? upload_attachments.size - 1 : nil,
            totalItemInGroup: upload_attachments.size > 1 ? upload_attachments.size : nil,
            mentionInfo: (mentions && is_group && upload_attachments.size == 1) ? mentions.to_json : nil
          }
        when 'video', 'others'
          {
            fileId: attachment[:fileId],
            checksum: attachment[:checksum],
            checksumSha: '',
            extention: ZCA::Utils.get_file_extension(attachment[:fileName]),
            totalSize: attachment[:totalSize],
            fileName: attachment[:fileName],
            clientId: attachment[:clientFileId],
            fType: 1,
            fileCount: 0,
            fdata: '{}',
            toid: is_group ? nil : thread_id.to_s,
            grid: is_group ? thread_id.to_s : nil,
            fileUrl: attachment[:fileUrl],
            zsource: -1,
            ttl: ttl || 0
          }
        else
          {}
        end.tap { |params| handle_urgency(params, urgency) }
      end

      def build_attachment_url(type, file_type)
        service_map = context.zpw_service_map
        base = if type == ZCA::Models::ThreadType::GROUP
          service_map['file'][0] + '/api/group/'
        else
          service_map['file'][0] + '/api/message/'
        end
        base + ATTACHMENT_URL_TYPE[file_type]
      end
    end
  end
end 