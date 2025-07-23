# frozen_string_literal: true

require 'ostruct'
require 'thread'
require 'http/cookie_jar'
require 'json'
require 'securerandom' # Added for imei generation

module ZCA
  module Types
    UploadEventData = Struct.new(:file_url, :file_id, keyword_init: true)
    ShareFileSettings = Struct.new(
      :big_file_domain_list, :max_size_share_file_v2, :max_size_share_file_v3,
      :file_upload_show_icon_1GB, :restricted_ext, :next_file_time, :max_file,
      :max_size_photo, :max_size_share_file, :max_size_resize_photo, :max_size_gif,
      :max_size_original_photo, :chunk_size_file, :restricted_ext_file,
      keyword_init: true
    )
    SocketSettings = Struct.new(
      :rotate_error_codes, :retries, :debug, :ping_interval, :reset_endpoint,
      :queue_ctrl_actionid_map, :close_and_retry_codes, :max_msg_size,
      :enable_ctrl_socket, :reconnect_after_fallback, :enable_chat_socket,
      :submit_wss_log, :disable_lp, :offline_monitor,
      keyword_init: true
    )
    LoginInfo = Struct.new(
      :haspcclient, :public_ip, :language, :send2me_id, :zpw_service_map_v3,
      keyword_init: true
    )
    ExtraVer = Struct.new(
      :phonebook, :conv_label, :friend, :ver_sticker_giphy_suggest, :ver_giphy_cate,
      :alias, :ver_sticker_cate_list, :block_friend,
      keyword_init: true
    )
  end

  module Cookie
    # Đơn giản hóa: dùng http-cookie để quản lý cookie jar
    class CookieJar < ::HTTP::CookieJar
      def to_json(*_args)
        cookies.map(&:to_h).to_json
      end
      def self.from_json(json)
        jar = new
        data = JSON.parse(json)
        cookies = data.is_a?(Hash) && data['cookies'].is_a?(Array) ? data['cookies'] : data
        cookies.each do |cookie_hash|
          jar << ::HTTP::Cookie.new(
            cookie_hash['name'],
            cookie_hash['value'],
            domain: cookie_hash['domain'],
            path: cookie_hash['path'],
            expires: cookie_hash['expirationDate'] ? Time.at(cookie_hash['expirationDate'].to_f) : nil,
            secure: cookie_hash['secure'],
            httponly: cookie_hash['httpOnly']
          )
        end
        jar
      end
    end
    # SerializedCookie: Hash dạng {name, value, domain, path, ...}
    # SerializedCookieJar: Array<SerializedCookie>
  end

  class CallbacksMap
    def initialize
      @map = {}
      @mutex = Mutex.new
    end

    def set(key, value, ttl = 5 * 60)
      @mutex.synchronize do
        @map[key] = value
        Thread.new do
          sleep(ttl)
          @mutex.synchronize { @map.delete(key) }
        end
      end
      self
    end

    def get(key)
      @mutex.synchronize { @map[key] }
    end

    def delete(key)
      @mutex.synchronize { @map.delete(key) }
    end
  end

  class AppContextBase < OpenStruct
    # Holds base context data
  end

  class AppContextExtended < OpenStruct
    # Holds extended context data
  end

  module Context
    API_TYPE_DEFAULT = 30
    API_VERSION_DEFAULT = 663
    MAX_MESSAGES_PER_SEND = 50

    def self.create_context(api_type = API_TYPE_DEFAULT, api_version = API_VERSION_DEFAULT, imei: nil)
      callbacks_map = CallbacksMap.new
      imei ||= SecureRandom.hex(16) # 32 ký tự hex, tương đương JS
      OpenStruct.new(
        API_TYPE: api_type,
        API_VERSION: api_version,
        upload_callbacks: callbacks_map,
        options: OpenStruct.new(
          self_listen: false,
          check_update: true,
          logging: true
        ),
        secret_key: nil,
        imei: imei
      )
    end

    def self.is_context_session?(ctx)
      !!ctx.secret_key
    end
  end
end 