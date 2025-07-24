# frozen_string_literal: true

require_relative '../utils'
require_relative '../models/attachment'
require 'json'
require 'uri'
require 'base64'
require 'openssl'

module ZCA
  module API
    class UploadAttachment
      include ZCA::Models

      URL_TYPE = {
        'image' => 'photo_original/upload',
        'video' => 'asyncfile/upload',
        'others' => 'asyncfile/upload'
      }
      IMAGE_EXTS = %w[jpg jpeg png webp]
      VIDEO_EXTS = %w[mp4]

      def initialize(context)
        @context = context
      end

      # sources: String (file path) hoặc AttachmentObject, hoặc mảng các loại đó
      # thread_id: id user hoặc group
      # type: :user hoặc :group
      def upload_attachment(sources, thread_id, type = :user)
        raise ZCA::Errors::ZaloApiError.new('Missing sources') if sources.nil? || (sources.respond_to?(:empty?) && sources.empty?)
        sources = [sources] unless sources.is_a?(Array)
        raise ZCA::Errors::ZaloApiError.new('Missing sources') if sources.empty?
        raise ZCA::Errors::ZaloApiError.new('Missing thread_id') if thread_id.nil? || thread_id.empty?

        # Lấy config chunk_size, max_file, max_size_share_file_v3 từ context.settings.features.sharefile
        sharefile = @context.settings.features.sharefile
        chunk_size = sharefile.chunk_size_file || (2 * 1024 * 1024)
        max_file = sharefile.max_file || 10
        max_size = sharefile.max_size_share_file_v3 ? sharefile.max_size_share_file_v3 * 1024 * 1024 : 20 * 1024 * 1024
        restricted_ext = sharefile.restricted_ext_file || []

        raise ZCA::Errors::ZaloApiError.new("Exceed maximum file of #{max_file}") if sources.size > max_file

        is_group = (type.to_s == 'group')
        service_url = @context.zpw_service_map['file'][0] + '/api/' + (is_group ? 'group/' : 'message/')
        type_param = is_group ? '11' : '2'

        client_id = (Time.now.to_f * 1000).to_i
        results = []

        sources.each do |source|
          is_file_path = source.is_a?(String)
          file_path = is_file_path ? source : source.filename
          ext = ZCA::Utils.get_file_extension(file_path).downcase
          file_name = ZCA::Utils.get_file_name(file_path)
          raise ZCA::Errors::ZaloApiError.new("File extension '#{ext}' is not allowed") if restricted_ext.include?(ext)

          file_type = if IMAGE_EXTS.include?(ext)
            'image'
          elsif VIDEO_EXTS.include?(ext)
            'video'
          else
            'others'
          end

          file_data = if is_file_path
            { fileName: file_name, totalSize: File.size(file_path) }
          else
            { fileName: file_name, totalSize: source.metadata&.total_size || source.data.bytesize }
          end

          raise ZCA::Errors::ZaloApiError.new("File #{file_name} size exceed maximum size of #{max_size/1024/1024}MB") if file_data[:totalSize] > max_size

          total_chunk = (file_data[:totalSize].to_f / chunk_size).ceil
          params = {
            totalChunk: total_chunk,
            fileName: file_name,
            clientId: client_id,
            totalSize: file_data[:totalSize],
            imei: @context.imei,
            isE2EE: 0,
            jxl: 0,
            chunkId: 1
          }
          is_group ? params[:grid] = thread_id : params[:toid] = thread_id

          file_buffer = is_file_path ? File.binread(file_path) : source.data

          (0...total_chunk).each do |i|
            chunk = file_buffer.byteslice(i * chunk_size, chunk_size)
            encrypted_params = ZCA::Utils.encode_aes(@context.secret_key, params.to_json)
            url = service_url + URL_TYPE[file_type]
            url = ZCA::Utils.make_url(@context, url, { type: type_param, params: encrypted_params })
            headers = {
              'content-type' => 'application/octet-stream',
              'accept' => 'application/json, text/plain, */*',
              'user-agent' => @context.userAgent || @context.user_agent || 'Mozilla/5.0'
            }
            resp = ZCA::Utils.request(@context, url, { method: :post, headers: headers, body: chunk }, :json)
            if resp.is_a?(String)
              resp = JSON.parse(resp)
            end
            if resp['error_code'] != 0
              raise ZCA::Errors::ZaloApiError.new(resp['error_message'], resp['error_code'])
            end
            # Giải mã response data nếu có
            if resp['data']
              decoded = ZCA::Utils.decode_zalo_response(@context.secret_key, resp['data'])
              results << decoded if decoded
            end
            params[:chunkId] += 1
          end
          client_id += 1
        end
        results
      end
    end
  end
end
