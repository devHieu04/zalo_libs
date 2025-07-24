# frozen_string_literal: true

require_relative 'base'
require_relative '../utils'
require_relative '../models/enum'
require_relative '../models/attachment'
require 'json'
require 'stringio'

module ZCA
  module API
    class UploadAttachment < Base
      URL_TYPE = {
        'image' => 'photo_original/upload',
        'video' => 'asyncfile/upload',
        'others' => 'asyncfile/upload'
      }.freeze

      # sources: String (file path) hoặc AttachmentObject, hoặc mảng các loại này
      # thread_id: id nhóm hoặc user
      # type: ZCA::Models::ThreadType::USER hoặc GROUP
      def upload_attachment(sources, thread_id, type = ZCA::Models::ThreadType::USER)
        sharefile = context.settings&.features&.sharefile
        raise ZCA::Errors::ZaloApiError.new('Missing sharefile settings') unless sharefile
        raise ZCA::Errors::ZaloApiError.new('Missing sources') if sources.nil?
        sources = [sources] unless sources.is_a?(Array)
        raise ZCA::Errors::ZaloApiError.new('Missing sources') if sources.empty?
        raise ZCA::Errors::ZaloApiError.new("Exceed maximum file of #{sharefile.max_file}") if sources.size > sharefile.max_file
        raise ZCA::Errors::ZaloApiError.new('Missing thread_id') if thread_id.nil? || thread_id.to_s.empty?

        chunk_size = sharefile.chunk_size_file
        is_group = (type == ZCA::Models::ThreadType::GROUP)
        service_url = context.zpw_service_map['file'][0] + '/api'
        url = service_url + "/#{is_group ? 'group' : 'message'}/"
        type_param = is_group ? '11' : '2'
        client_id = (Time.now.to_f * 1000).to_i
        attachments_data = []

        sources.each do |source|
          is_file_path = source.is_a?(String)
          is_buffer = source.respond_to?(:data)
          file_name = is_file_path ? ZCA::Utils.get_file_name(source) : source.filename
          ext_file = ZCA::Utils.get_file_extension(is_file_path ? source : source.filename)
          raise ZCA::Errors::ZaloApiError.new("File extension '#{ext_file}' is not allowed") if sharefile.restricted_ext_file.include?(ext_file)

          file_data = nil
          file_type = nil
          total_size = nil
          width = nil
          height = nil

          if is_file_path && !File.exist?(source)
            raise ZCA::Errors::ZaloApiError.new("File not found: #{source}")
          end

          case ext_file
          when 'jpg', 'jpeg', 'png', 'webp'
            # Lấy metadata ảnh
            if is_file_path
              require 'fastimage'
              size = FastImage.size(source)
              total_size = File.size(source)
              width, height = size
            else
              width = source.metadata&.width
              height = source.metadata&.height
              total_size = source.metadata&.total_size
            end
            raise ZCA::Errors::ZaloApiError.new("File #{file_name} size exceed maximum size of #{sharefile.max_size_share_file_v3}MB") if total_size > sharefile.max_size_share_file_v3 * 1024 * 1024

            file_data = OpenStruct.new(file_name: file_name, total_size: total_size, width: width, height: height)
            file_type = 'image'
          when 'mp4'
            total_size = is_file_path ? File.size(source) : source.metadata&.total_size
            raise ZCA::Errors::ZaloApiError.new("File #{file_name} size exceed maximum size of #{sharefile.max_size_share_file_v3}MB") if total_size > sharefile.max_size_share_file_v3 * 1024 * 1024

            file_data = OpenStruct.new(file_name: file_name, total_size: total_size)
            file_type = 'video'
          else
            total_size = is_file_path ? File.size(source) : source.metadata&.total_size
            raise ZCA::Errors::ZaloApiError.new("File #{file_name} size exceed maximum size of #{sharefile.max_size_share_file_v3}MB") if total_size > sharefile.max_size_share_file_v3 * 1024 * 1024

            file_data = OpenStruct.new(file_name: file_name, total_size: total_size)
            file_type = 'others'
          end

          total_chunk = (total_size.to_f / chunk_size).ceil
          params = {
            fileName: file_name,
            clientId: client_id,
            totalSize: total_size,
            imei: context.imei,
            isE2EE: 0,
            jxl: 0,
            chunkId: 1,
            totalChunk: total_chunk
          }
          is_group ? params[:grid] = thread_id : params[:toid] = thread_id

          file_buffer = if is_file_path
            File.binread(source)
          else
            source.data
          end

          attachments_data << {
            file_path: is_file_path ? source : source.filename,
            file_type: file_type,
            file_data: file_data,
            params: params,
            file_buffer: file_buffer,
            source: source
          }
          client_id += 1
        end

        results = []
        attachments_data.each do |data|
          (0...data[:params][:totalChunk]).each do |i|
            chunk = data[:file_buffer][i * chunk_size, chunk_size]
            encrypted_params = ZCA::Utils.encode_aes(context.secret_key, data[:params].to_json)
            raise ZCA::Errors::ZaloApiError.new('Failed to encrypt message') unless encrypted_params
            # Sửa: truyền thêm nretry: 0 vào make_url để đảm bảo luôn có zpw_type, zpw_ver
            request_url = ZCA::Utils.make_url(context, url + URL_TYPE[data[:file_type]], { type: type_param, params: encrypted_params, nretry: 0 })
            headers = {
              'Content-Type' => 'application/octet-stream',
              'User-Agent' => context.userAgent || context.user_agent || 'Mozilla/5.0',
              'Accept' => '*/*',
              'Accept-Language' => 'vi-VN,vi;q=0.9,fr-FR;q=0.8,fr;q=0.7,en-US;q=0.6,en;q=0.5',
              'Referer' => 'https://chat.zalo.me/'
            }
            resp = ZCA::Utils.request(context, request_url, {
              method: :post,
              headers: headers,
              body: chunk
            })
            res_data = resp.is_a?(String) ? JSON.parse(resp) : resp
            # Xử lý callback cho video/others
            if res_data && res_data['fileId'].to_i != -1 && res_data['photoId'].to_i != -1
              if data[:file_type] == 'video' || data[:file_type] == 'others'
                upload_callback = proc do |ws_data|
                  checksum = ZCA::Utils.get_md5_large_file_object(data[:source], data[:file_data].total_size)[:data]
                  result = {
                    fileType: data[:file_type],
                    **res_data,
                    **ws_data,
                    totalSize: data[:file_data].total_size,
                    fileName: data[:file_data].file_name,
                    checksum: checksum
                  }
                  results << result
                end
                context.upload_callbacks.set(res_data['fileId'], upload_callback)
              elsif data[:file_type] == 'image'
                result = {
                  fileType: 'image',
                  width: data[:file_data].width,
                  height: data[:file_data].height,
                  totalSize: data[:file_data].total_size,
                  hdSize: data[:file_data].total_size,
                  **res_data
                }
                results << result
              end
            end
            data[:params][:chunkId] += 1
          end
        end
        results
      end
    end
  end
end 