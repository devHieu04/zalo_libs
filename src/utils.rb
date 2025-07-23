# frozen_string_literal: true

require 'digest'
require 'uri'
require 'ostruct'
require 'time'
require 'openssl'
require 'securerandom'
require 'base64'
require 'zlib'
require 'httparty'
require 'json' # Added for JSON parsing

# Custom error class
class ZaloApiError < StandardError
  attr_reader :code
  def initialize(message, code = nil)
    super(message)
    @code = code
  end
end

# Enum for group events
module GroupEventType
  JOIN_REQUEST = 0
  JOIN = 1
  LEAVE = 2
  REMOVE_MEMBER = 3
  BLOCK_MEMBER = 4
  UPDATE_SETTING = 5
  UPDATE = 6
  NEW_LINK = 7
  ADD_ADMIN = 8
  REMOVE_ADMIN = 9
  NEW_PIN_TOPIC = 10
  UPDATE_PIN_TOPIC = 11
  REORDER_PIN_TOPIC = 12
  UPDATE_BOARD = 13
  REMOVE_BOARD = 14
  UPDATE_TOPIC = 15
  UNPIN_TOPIC = 16
  REMOVE_TOPIC = 17
  ACCEPT_REMIND = 18
  REJECT_REMIND = 19
  REMIND_TOPIC = 20
  UPDATE_AVATAR = 21
  UNKNOWN = 22
end

# Enum for friend events
module FriendEventType
  ADD = 0
  REMOVE = 1
  REQUEST = 2
  UNDO_REQUEST = 3
  REJECT_REQUEST = 4
  SEEN_FRIEND_REQUEST = 5
  BLOCK = 6
  UNBLOCK = 7
  BLOCK_CALL = 8
  UNBLOCK_CALL = 9
  PIN_UNPIN = 10
  PIN_CREATE = 11
  UNKNOWN = 12
end

module ZCA
  module Utils
    def self.get_sign_key(type, params)
      keys = params.keys.sort
      a = "zsecure" + type.to_s
      keys.each { |k| a += params[k].to_s }
      Digest::MD5.hexdigest(a)
    end

    def self.make_url(ctx, base_url, params = {}, api_version = true)
      uri = URI(base_url)
      query = URI.decode_www_form(uri.query || '')
      params.each { |k, v| query << [k.to_s, v.to_s] }
      if api_version
        query << ["zpw_ver", ctx.API_VERSION.to_s] unless query.any? { |k, _| k == "zpw_ver" }
        query << ["zpw_type", ctx.API_TYPE.to_s] unless query.any? { |k, _| k == "zpw_type" }
      end
      uri.query = URI.encode_www_form(query)
      uri.to_s
    end

    def self.str_pad_left(e, t, n)
      e = e.to_s
      a = e.length
      return e if a == n
      return e[-n, n] if a > n
      t * (n - a) + e
    end

    def self.format_time(format, timestamp = Time.now.to_i * 1000)
      time = Time.at(timestamp / 1000)
      if format.include?("%H") || format.include?("%d")
        format
          .gsub("%H", time.hour.to_s.rjust(2, '0'))
          .gsub("%M", time.min.to_s.rjust(2, '0'))
          .gsub("%S", time.sec.to_s.rjust(2, '0'))
          .gsub("%d", time.day.to_s.rjust(2, '0'))
          .gsub("%m", time.month.to_s.rjust(2, '0'))
          .gsub("%Y", time.year.to_s)
      else
        time.strftime("%d/%m/%Y %H:%M:%S")
      end
    end

    def self.get_file_extension(e)
      File.extname(e).sub(/^\./, '')
    end

    def self.get_file_name(e)
      File.basename(e)
    end

    def self.remove_undefined_keys(hash)
      hash.delete_if { |_, v| v.nil? }
      hash
    end

    def self.encrypt_pin(pin)
      Digest::MD5.hexdigest(pin)
    end

    def self.validate_pin(encrypted_pin, pin)
      Digest::MD5.hexdigest(pin) == encrypted_pin
    end

    def self.hex_to_negative_color(hex)
      hex = "##{hex}" unless hex.start_with?('#')
      hex_value = hex[1..]
      hex_value = "FF" + hex_value if hex_value.length == 6
      decimal = hex_value.to_i(16)
      decimal > 0x7fffffff ? decimal - 4294967296 : decimal
    end

    def self.negative_color_to_hex(negative_color)
      positive_color = negative_color + 4294967296
      "#" + positive_color.to_s(16)[-6..].rjust(6, '0')
    end

    class ParamsEncryptor
      attr_reader :zcid, :enc_ver, :zcid_ext, :encrypt_key
      def initialize(type:, imei:, first_launch_time:)
        @enc_ver = 'v2'
        @zcid = nil
        @encrypt_key = nil
        create_zcid(type, imei, first_launch_time)
        @zcid_ext = ParamsEncryptor.random_string
        create_encrypt_key
      end

      def get_encrypt_key
        raise ZaloApiError.new("getEncryptKey: didn't create encryptKey yet") unless @encrypt_key
        @encrypt_key
      end

      def create_zcid(type, imei, first_launch_time)
        raise ZaloApiError.new("createZcid: missing params") unless type && imei && first_launch_time
        msg = "#{type},#{imei},#{first_launch_time}"
        @zcid = ParamsEncryptor.encode_aes('3FC4F0D2AB50057BCE0D90D9187A22B1', msg, :hex, true)
      end

      def create_encrypt_key(e = 0)
        raise ZaloApiError.new("createEncryptKey: zcid or zcid_ext is null") unless @zcid && @zcid_ext
        begin
          n = Digest::MD5.hexdigest(@zcid_ext).upcase
          if _try_create_key(n, @zcid) || e >= 3
            return true
          else
            create_encrypt_key(e + 1)
          end
        rescue
          create_encrypt_key(e + 1) if e < 3
        end
        true
      end

      def _try_create_key(e, t)
        n = ParamsEncryptor.process_str(e)[:even]
        a = ParamsEncryptor.process_str(t)[:even]
        s = ParamsEncryptor.process_str(t)[:odd]
        return false unless n && a && s
        i = n[0,8].join + a[0,12].join + s.reverse[0,12].join
        @encrypt_key = i
        true
      end

      def get_params
        return nil unless @zcid
        { zcid: @zcid, zcid_ext: @zcid_ext, enc_ver: @enc_ver }
      end

      def self.process_str(e)
        return { even: nil, odd: nil } unless e.is_a?(String)
        chars = e.chars
        even, odd = [], []
        chars.each_with_index { |c, i| (i.even? ? even : odd) << c }
        { even: even, odd: odd }
      end

      def self.random_string(min = 6, max = 12)
        len = rand(min..max)
        SecureRandom.hex((len/2.0).ceil)[0,len]
      end

      def self.encode_aes(key, message, type, uppercase, s = 0)
        return nil unless message
        begin
          cipher = OpenSSL::Cipher.new('AES-128-CBC')
          cipher.encrypt
          cipher.key = [key].pack('H*')
          cipher.iv = ["00"*16].pack('H*')
          encrypted = cipher.update(message) + cipher.final
          result =
            case type
            when :hex
              encrypted.unpack1('H*')
            when :base64
              Base64.strict_encode64(encrypted)
            end
          uppercase ? result.upcase : result
        rescue
          s < 3 ? encode_aes(key, message, type, uppercase, s+1) : nil
        end
      end
    end

    def self.decode_base64_to_buffer(data)
      Base64.decode64(data)
    end

    def self.encode_aes(secret_key, data, t = 0)
      begin
        cipher = OpenSSL::Cipher.new('AES-128-CBC')
        cipher.encrypt
        cipher.key = Base64.decode64(secret_key)
        cipher.iv = ["00"*16].pack('H*')
        encrypted = cipher.update(data) + cipher.final
        Base64.strict_encode64(encrypted)
      rescue
        t < 3 ? encode_aes(secret_key, data, t+1) : nil
      end
    end

    def self.decode_aes(secret_key, data, t = 0)
      begin
        data = URI.decode_www_form_component(data)
        decipher = OpenSSL::Cipher.new('AES-128-CBC')
        decipher.decrypt
        decipher.key = Base64.decode64(secret_key)
        decipher.iv = ["00"*16].pack('H*')
        decrypted = decipher.update(Base64.decode64(data)) + decipher.final
        decrypted.force_encoding('UTF-8')
      rescue
        t < 3 ? decode_aes(secret_key, data, t+1) : nil
      end
    end

    def self.decrypt_resp(secret_key, data, t = 0)
      begin
        decipher = OpenSSL::Cipher.new('AES-128-CBC')
        decipher.decrypt
        decipher.key = [secret_key].pack('H*')
        decipher.iv = ["00"*16].pack('H*')
        decrypted = decipher.update(Base64.decode64(data)) + decipher.final
        decrypted.force_encoding('UTF-8')
      rescue
        t < 3 ? decrypt_resp(secret_key, data, t+1) : nil
      end
    end

    def self.logger(ctx)
      Module.new do
        define_singleton_method(:verbose) { |*args| puts "\e[35m🚀 VERBOSE\e[0m", *args if ctx.options.logging }
        define_singleton_method(:info)    { |*args| puts "\e[34mINFO\e[0m", *args if ctx.options.logging }
        define_singleton_method(:warn)    { |*args| puts "\e[33mWARN\e[0m", *args if ctx.options.logging }
        define_singleton_method(:error)   { |*args| puts "\e[31mERROR\e[0m", *args if ctx.options.logging }
        define_singleton_method(:success) { |*args| puts "\e[32mSUCCESS\e[0m", *args if ctx.options.logging }
        define_singleton_method(:timestamp) do |*args|
          now = Time.now.utc.iso8601
          puts "\e[90m[#{now}]\e[0m", *args if ctx.options.logging
        end
      end
    end

    def self.get_client_message_type(msg_type)
      case msg_type
      when 'webchat' then 1
      when 'chat.voice' then 31
      when 'chat.photo' then 32
      when 'chat.sticker' then 36
      when 'chat.doodle' then 37
      when 'chat.recommended', 'chat.link' then 38
      when 'chat.video.msg' then 44
      when 'share.file' then 46
      when 'chat.gif' then 49
      when 'chat.location.new' then 43
      else 1
      end
    end

    def self.get_group_event_type(act)
      case act
      when 'join_request' then GroupEventType::JOIN_REQUEST
      when 'join' then GroupEventType::JOIN
      when 'leave' then GroupEventType::LEAVE
      when 'remove_member' then GroupEventType::REMOVE_MEMBER
      when 'block_member' then GroupEventType::BLOCK_MEMBER
      when 'update_setting' then GroupEventType::UPDATE_SETTING
      when 'update_avatar' then GroupEventType::UPDATE_AVATAR
      when 'update' then GroupEventType::UPDATE
      when 'new_link' then GroupEventType::NEW_LINK
      when 'add_admin' then GroupEventType::ADD_ADMIN
      when 'remove_admin' then GroupEventType::REMOVE_ADMIN
      when 'new_pin_topic' then GroupEventType::NEW_PIN_TOPIC
      when 'update_pin_topic' then GroupEventType::UPDATE_PIN_TOPIC
      when 'update_topic' then GroupEventType::UPDATE_TOPIC
      when 'update_board' then GroupEventType::UPDATE_BOARD
      when 'remove_board' then GroupEventType::REMOVE_BOARD
      when 'reorder_pin_topic' then GroupEventType::REORDER_PIN_TOPIC
      when 'unpin_topic' then GroupEventType::UNPIN_TOPIC
      when 'remove_topic' then GroupEventType::REMOVE_TOPIC
      when 'accept_remind' then GroupEventType::ACCEPT_REMIND
      when 'reject_remind' then GroupEventType::REJECT_REMIND
      when 'remind_topic' then GroupEventType::REMIND_TOPIC
      else GroupEventType::UNKNOWN
      end
    end

    def self.get_friend_event_type(act)
      case act
      when 'add' then FriendEventType::ADD
      when 'remove' then FriendEventType::REMOVE
      when 'block' then FriendEventType::BLOCK
      when 'unblock' then FriendEventType::UNBLOCK
      when 'block_call' then FriendEventType::BLOCK_CALL
      when 'unblock_call' then FriendEventType::UNBLOCK_CALL
      when 'req_v2' then FriendEventType::REQUEST
      when 'reject' then FriendEventType::REJECT_REQUEST
      when 'undo_req' then FriendEventType::UNDO_REQUEST
      when 'seen_fr_req' then FriendEventType::SEEN_FRIEND_REQUEST
      when 'pin_unpin' then FriendEventType::PIN_UNPIN
      when 'pin_create' then FriendEventType::PIN_CREATE
      else FriendEventType::UNKNOWN
      end
    end

    def self.get_md5_large_file_object(source, file_size)
      chunk_size = 2 * 1024 * 1024 # 2MB
      chunks = (file_size.to_f / chunk_size).ceil
      current_chunk = 0
      md5 = Digest::MD5.new
      buffer =
        if source.is_a?(String)
          File.binread(source)
        elsif source.respond_to?(:data)
          source.data
        else
          raise ArgumentError, 'Invalid source type'
        end
      while current_chunk < chunks
        start = current_chunk * chunk_size
        end_pos = [start + chunk_size, file_size].min
        md5.update(buffer[start...end_pos])
        current_chunk += 1
      end
      { current_chunk: current_chunk, data: md5.hexdigest }
    end

    def self.decompress_gzip(data)
      Zlib::GzipReader.new(StringIO.new(data)).read
    end

    # request nâng cao: hỗ trợ proxy, timeout, retry, stream, debug, response_type
    # options:
    #   :headers, :body, :query, :method, :multipart, :proxy, :timeout, :open_timeout, :read_timeout,
    #   :max_retries, :follow_redirects, :stream, :debug, :response_type (:json, :text, :raw, :file)
    def self.request(ctx, url, options = {}, raw = false)
      default_headers = {
        'User-Agent' => ctx.respond_to?(:userAgent) && ctx.userAgent ? ctx.userAgent : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept' => '*/*',
        'Accept-Language' => 'vi-VN,vi;q=0.9,fr-FR;q=0.8,fr;q=0.7,en-US;q=0.6,en;q=0.5',
        'Referer' => 'https://chat.zalo.me/'
      }
      headers = default_headers.merge(options[:headers] || {})
      # Cookie xử lý nâng cao
      if ctx.respond_to?(:cookie) && ctx.cookie
        if ctx.cookie.is_a?(HTTP::CookieJar)
          cookies = ctx.cookie.cookies(URI(url)).map { |c| "#{c.name}=#{c.value}" }.join('; ')
          headers['Cookie'] = cookies unless cookies.empty?
        elsif ctx.cookie.is_a?(String)
          headers['Cookie'] ||= ctx.cookie
        elsif ctx.cookie.respond_to?(:to_cookie_string)
          headers['Cookie'] ||= ctx.cookie.to_cookie_string
        end
      end
      # Content-Type cho POST nếu chưa có
      if (options[:method]&.to_s&.downcase == 'post' || options[:body]) && !headers['Content-Type']
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
      end
      method = (options[:method] || :get).to_sym
      query = options[:query]
      body = options[:body]
      multipart = options[:multipart]
      proxy = options[:proxy]
      timeout = options[:timeout]
      open_timeout = options[:open_timeout]
      read_timeout = options[:read_timeout]
      max_retries = options[:max_retries] || 0
      follow_redirects = options.key?(:follow_redirects) ? options[:follow_redirects] : true
      debug = options[:debug]
      response_type = options[:response_type] || :auto
      stream = options[:stream]
      file_path = options[:file_path]

      httparty_opts = {
        headers: headers,
        query: query,
        body: body,
        follow_redirects: follow_redirects
      }
      httparty_opts.delete(:body) if body.nil?
      httparty_opts.delete(:query) if query.nil?
      httparty_opts[:http_proxyaddr], httparty_opts[:http_proxyport] = proxy.split("://")[1].split(":") if proxy
      httparty_opts[:timeout] = timeout if timeout
      httparty_opts[:open_timeout] = open_timeout if open_timeout
      httparty_opts[:read_timeout] = read_timeout if read_timeout
      if multipart && body.is_a?(Hash)
        httparty_opts[:body] = body
        httparty_opts[:multipart] = true
      end
      httparty_opts[:stream_body] = true if stream

      attempt = 0
      begin
        attempt += 1
        response = HTTParty.send(method, url, httparty_opts) do |fragment|
          if stream && block_given?
            yield fragment
          elsif stream && stream.respond_to?(:call)
            stream.call(fragment)
          end
        end
        puts "[HTTP DEBUG] #{method.upcase} #{url} => #{response.code}" if debug
        puts "[HTTP DEBUG] Headers: #{headers.inspect}" if debug
        puts "[HTTP DEBUG] Response headers: #{response.headers.inspect}" if debug
        puts "[HTTP DEBUG] Body: #{response.body[0..500]}..." if debug && response.body
        # Cập nhật cookie nếu ctx.cookie là HTTP::CookieJar hoặc tương tự
        if ctx.respond_to?(:cookie) && ctx.cookie.is_a?(HTTP::CookieJar) && response.headers['set-cookie']
          Array(response.headers['set-cookie']).each do |set_cookie|
            HTTP::Cookie.parse(set_cookie, url).each { |cookie| ctx.cookie.add(cookie) }
          end
        elsif ctx.respond_to?(:cookie) && ctx.cookie && response.headers['set-cookie']
          if ctx.cookie.respond_to?(:add_cookies)
            ctx.cookie.add_cookies(response.headers['set-cookie'])
          end
        end
        unless response.success?
          # Nếu là 302 và follow_redirects=false thì trả về response cho caller tự xử lý
          if response.code.to_i == 302 && follow_redirects == false
            return response
          end
          raise ZaloApiError.new("Request failed with status code #{response.code}", response.code)
        end
        return response if raw || response_type == :raw
        content_type = response.headers['content-type']
        if response_type == :json || (response_type == :auto && content_type&.include?('application/json'))
          begin
            return JSON.parse(response.body)
          rescue
            return response.body
          end
        elsif response_type == :file && file_path
          File.open(file_path, 'wb') { |f| f.write(response.body) }
          return file_path
        else
          return response.body
        end
      rescue => e
        if max_retries > 0 && attempt <= max_retries
          sleep(0.5 * attempt)
          retry
        end
        raise ZaloApiError.new("HTTP request error: #{e.message}")
      end
    end
  end
end 