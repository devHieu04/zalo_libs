# frozen_string_literal: true

require_relative 'base'
require_relative '../utils'
require 'base64'
require 'fileutils'
require 'net/http/post/multipart'

module ZCA
  module API
    # Enum cho callback event type
    module LoginQRCallbackEventType
      QRCodeGenerated = :QRCodeGenerated
      QRCodeExpired = :QRCodeExpired
      QRCodeScanned = :QRCodeScanned
      QRCodeDeclined = :QRCodeDeclined
      GotLoginInfo = :GotLoginInfo
    end

    # Struct cho từng loại event callback
    LoginQRCallbackEvent = Struct.new(:type, :data, :actions, keyword_init: true)
    # LoginQRCallback: Proc nhận LoginQRCallbackEvent
    # Ví dụ: callback = ->(event) { ... }
    class LoginQR < Base
      QR_EXPIRE_TIMEOUT = 100 # seconds

      def login_qr(user_agent:, qr_path: 'qr.png', &callback)
        context.cookie = ZCA::Cookie::CookieJar.new
        context.userAgent = user_agent
        login_version = load_login_page
        raise ZCA::Errors::ZaloApiError.new('Cannot get API login version') unless login_version
        Utils.logger(context).info("Got login version:", login_version)
        login_info_resp = get_login_info(login_version)
        if !login_info_resp || (login_info_resp.is_a?(Hash) && login_info_resp['error_code'] && login_info_resp['error_code'] != 0)
          Utils.logger(context).error("get_login_info response:", login_info_resp.inspect)
          raise ZCA::Errors::ZaloApiError.new("get_login_info failed: #{login_info_resp.inspect}")
        end
        verify_client_resp = verify_client(login_version)
        if !verify_client_resp || (verify_client_resp.is_a?(Hash) && verify_client_resp['error_code'] && verify_client_resp['error_code'] != 0)
          Utils.logger(context).error("verify_client response:", verify_client_resp.inspect)
          raise ZCA::Errors::ZaloApiError.new("verify_client failed: #{verify_client_resp.inspect}")
        end
        qr_gen_result = generate_qr(login_version)
        qr_gen_result = qr_gen_result.is_a?(HTTParty::Response) ? qr_gen_result.parsed_response : qr_gen_result
        unless qr_gen_result && qr_gen_result['data']
          Utils.logger(context).error("generate_qr response:", qr_gen_result.inspect)
          raise ZCA::Errors::ZaloApiError.new("Unable to generate QRCode. Response: #{qr_gen_result.inspect}")
        end
        qr_data = qr_gen_result['data']
        image_data = qr_data['image'].sub(/^data:image\/png;base64,/, '')
        code = qr_data['code']
        expired = false
        result = nil
        retry_proc = -> { login_qr(user_agent: user_agent, qr_path: qr_path, &callback) }
        abort_proc = -> { expired = true }
        if callback
          callback.call({
            type: LoginQRCallbackEventType::QRCodeGenerated,
            data: qr_data.merge('image' => image_data),
            actions: {
              save_to_file: ->(*args) {
                # Hỗ trợ truyền path, bot_token:, chat_id:
                opts = args.last.is_a?(Hash) ? args.pop : {}
                path = args.first || qr_path
                save_qr_code_to_file(path, image_data, **opts)
              },
              retry: retry_proc,
              abort: abort_proc,
            }
          })
        else
          save_qr_code_to_file(qr_path, image_data)
          Utils.logger(context).info("Scan the QR code at '#{qr_path}' to proceed with login")
        end
        # Thread timeout QR
        timeout_thread = Thread.new do
          sleep(QR_EXPIRE_TIMEOUT)
          expired = true
          Utils.logger(context).info("QR expired!")
          if callback
            callback.call({
              type: LoginQRCallbackEventType::QRCodeExpired,
              data: nil,
              actions: {
                retry: retry_proc,
                abort: abort_proc,
              }
            })
          end
        end
        # Chờ user quét QR (polling)
        scan_result = nil
        until expired
          scan_result = waiting_scan(login_version, code)
          scan_result = scan_result.is_a?(HTTParty::Response) ? scan_result.parsed_response : scan_result
          break if scan_result && scan_result['data']
          sleep 2
        end
        if expired
          timeout_thread.kill if timeout_thread.alive?
          return nil
        end
        if callback
          callback.call({
            type: LoginQRCallbackEventType::QRCodeScanned,
            data: scan_result['data'],
            actions: {
              retry: retry_proc,
              abort: abort_proc,
            }
          })
        end
        # Tiếp tục xác nhận, check session, get user info
        confirm_result = waiting_confirm(login_version, code)
        confirm_result = confirm_result.is_a?(HTTParty::Response) ? confirm_result.parsed_response : confirm_result
        return nil unless confirm_result
        check_session_result = check_session
        if check_session_result.respond_to?(:code)
          code = check_session_result.code.to_i
          unless [200, 302].include?(code)
            raise ZCA::Errors::ZaloApiError.new("Check session failed, HTTP status: #{code}")
          end
        end
        return nil unless check_session_result
        if confirm_result['error_code'] == 0
          Utils.logger(context).info("Successfully logged into the account", scan_result['data']['display_name'])
        elsif confirm_result['error_code'] == -13
          if callback
            callback.call({
              type: LoginQRCallbackEventType::QRCodeDeclined,
              data: { code: code },
              actions: {
                retry: retry_proc,
                abort: abort_proc,
              }
            })
          else
            Utils.logger(context).error("QRCode login declined")
            return nil
          end
          return nil
        else
          raise ZCA::Errors::ZaloApiError.new("An error has occurred. Response: #{confirm_result.inspect}")
        end
        user_info = get_user_info
        user_info = user_info.is_a?(HTTParty::Response) ? user_info.parsed_response : user_info
        puts "[DEBUG] user_info: #{user_info.inspect}" # Thêm log debug
        raise ZCA::Errors::ZaloApiError.new("Can't get account info") unless user_info && user_info['data']
        raise ZCA::Errors::ZaloApiError.new("Can't login") unless user_info['data']['logged']
        timeout_thread.kill if timeout_thread.alive?
        {
          cookies: context.cookie, # cần serialize nếu muốn
          user_info: user_info['data']['info']
        }
      end

      private

      def load_login_page
        url = 'https://id.zalo.me/account?continue=https%3A%2F%2Fchat.zalo.me%2F'
        html = Utils.request(context, url, { method: :get }, :text)
        match = html.match(%r{https://stc-zlogin\.zdn\.vn/main-([\d.]+)\.js})
        match ? match[1] : nil
      end

      def get_login_info(version)
        url = 'https://id.zalo.me/account/logininfo'
        body = URI.encode_www_form(continue: 'https://zalo.me/pc', v: version, imei: context.imei)
        headers = {
          'accept' => '*/*',
          'accept-language' => 'vi-VN,vi;q=0.9,fr-FR;q=0.8,fr;q=0.7,en-US;q=0.6,en;q=0.5',
          'content-type' => 'application/x-www-form-urlencoded',
          'priority' => 'u=1, i',
          'sec-ch-ua' => '"Chromium";v="130", "Google Chrome";v="130", "Not?A_Brand";v="99"',
          'sec-ch-ua-mobile' => '?0',
          'sec-ch-ua-platform' => '"Windows"',
          'sec-fetch-dest' => 'empty',
          'sec-fetch-mode' => 'cors',
          'sec-fetch-site' => 'same-origin',
          'referer' => 'https://id.zalo.me/account?continue=https%3A%2F%2Fzalo.me%2Fpc',
          'referrer-policy' => 'strict-origin-when-cross-origin'
        }
        Utils.request(context, url, { method: :post, headers: headers, body: body }, :json)
      end

      def verify_client(version)
        url = 'https://id.zalo.me/account/verify-client'
        body = URI.encode_www_form(type: 'device', continue: 'https://zalo.me/pc', v: version, imei: context.imei)
        headers = {
          'accept' => '*/*',
          'accept-language' => 'vi-VN,vi;q=0.9,fr-FR;q=0.8,fr;q=0.7,en-US;q=0.6,en;q=0.5',
          'content-type' => 'application/x-www-form-urlencoded',
          'priority' => 'u=1, i',
          'sec-ch-ua' => '"Chromium";v="130", "Google Chrome";v="130", "Not?A_Brand";v="99"',
          'sec-ch-ua-mobile' => '?0',
          'sec-ch-ua-platform' => '"Windows"',
          'sec-fetch-dest' => 'empty',
          'sec-fetch-mode' => 'cors',
          'sec-fetch-site' => 'same-origin',
          'referer' => 'https://id.zalo.me/account?continue=https%3A%2F%2Fzalo.me%2Fpc',
          'referrer-policy' => 'strict-origin-when-cross-origin'
        }
        Utils.request(context, url, { method: :post, headers: headers, body: body }, :json)
      end

      def generate_qr(version)
        url = 'https://id.zalo.me/account/authen/qr/generate'
        body = URI.encode_www_form(continue: 'https://zalo.me/pc', v: version, imei: context.imei)
        headers = {
          'accept' => '*/*',
          'accept-language' => 'vi-VN,vi;q=0.9,fr-FR;q=0.8,fr;q=0.7,en-US;q=0.6,en;q=0.5',
          'content-type' => 'application/x-www-form-urlencoded',
          'priority' => 'u=1, i',
          'sec-ch-ua' => '"Chromium";v="130", "Google Chrome";v="130", "Not?A_Brand";v="99"',
          'sec-ch-ua-mobile' => '?0',
          'sec-ch-ua-platform' => '"Windows"',
          'sec-fetch-dest' => 'empty',
          'sec-fetch-mode' => 'cors',
          'sec-fetch-site' => 'same-origin',
          'referer' => 'https://id.zalo.me/account?continue=https%3A%2F%2Fzalo.me%2Fpc',
          'referrer-policy' => 'strict-origin-when-cross-origin'
        }
        Utils.request(context, url, { method: :post, headers: headers, body: body }, :json)
      end

      def waiting_scan(version, code)
        url = 'https://id.zalo.me/account/authen/qr/waiting-scan'
        body = URI.encode_www_form(code: code, continue: 'https://chat.zalo.me/', v: version, imei: context.imei)
        headers = {
          'accept' => '*/*',
          'accept-language' => 'vi-VN,vi;q=0.9,fr-FR;q=0.8,fr;q=0.7,en-US;q=0.6,en;q=0.5',
          'content-type' => 'application/x-www-form-urlencoded',
          'priority' => 'u=1, i',
          'sec-ch-ua' => '"Chromium";v="130", "Google Chrome";v="130", "Not?A_Brand";v="99"',
          'sec-ch-ua-mobile' => '?0',
          'sec-ch-ua-platform' => '"Windows"',
          'sec-fetch-dest' => 'empty',
          'sec-fetch-mode' => 'cors',
          'sec-fetch-site' => 'same-origin',
          'referer' => 'https://id.zalo.me/account?continue=https%3A%2F%2Fchat.zalo.me%2F',
          'referrer-policy' => 'strict-origin-when-cross-origin'
        }
        Utils.request(context, url, { method: :post, headers: headers, body: body }, :json)
      end

      def waiting_confirm(version, code)
        url = 'https://id.zalo.me/account/authen/qr/waiting-confirm'
        body = URI.encode_www_form(code: code, gToken: '', gAction: 'CONFIRM_QR', continue: 'https://chat.zalo.me/', v: version, imei: context.imei)
        headers = {
          'accept' => '*/*',
          'accept-language' => 'vi-VN,vi;q=0.9,fr-FR;q=0.8,fr;q=0.7,en-US;q=0.6,en;q=0.5',
          'content-type' => 'application/x-www-form-urlencoded',
          'priority' => 'u=1, i',
          'sec-ch-ua' => '"Chromium";v="130", "Google Chrome";v="130", "Not?A_Brand";v="99"',
          'sec-ch-ua-mobile' => '?0',
          'sec-ch-ua-platform' => '"Windows"',
          'sec-fetch-dest' => 'empty',
          'sec-fetch-mode' => 'cors',
          'sec-fetch-site' => 'same-origin',
          'referer' => 'https://id.zalo.me/account?continue=https%3A%2F%2Fchat.zalo.me%2F',
          'referrer-policy' => 'strict-origin-when-cross-origin'
        }
        Utils.logger(context).info('Please confirm on your phone')
        Utils.request(context, url, { method: :post, headers: headers, body: body }, :json)
      end

      def check_session
        url = 'https://id.zalo.me/account/checksession?continue=https%3A%2F%2Fchat.zalo.me%2Findex.html'
        headers = {
          'accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
          'accept-language' => 'vi-VN,vi;q=0.9,fr-FR;q=0.8,fr;q=0.7,en-US;q=0.6,en;q=0.5',
          'priority' => 'u=0, i',
          'sec-ch-ua' => '"Chromium";v="130", "Google Chrome";v="130", "Not?A_Brand";v="99"',
          'sec-ch-ua-mobile' => '?0',
          'sec-ch-ua-platform' => '"Windows"',
          'sec-fetch-dest' => 'document',
          'sec-fetch-mode' => 'navigate',
          'sec-fetch-site' => 'same-origin',
          'upgrade-insecure-requests' => '1',
          'referer' => 'https://id.zalo.me/account?continue=https%3A%2F%2Fchat.zalo.me%2F',
          'referrer-policy' => 'strict-origin-when-cross-origin'
        }
        # Lấy response gốc để lấy header
        resp = Utils.request(context, url, { method: :get, headers: headers, follow_redirects: false }, :raw)
        # Cập nhật cookie từ header set-cookie
        if resp.respond_to?(:headers) && resp.headers['set-cookie']
          require 'http/cookie'
          set_cookies = [resp.headers['set-cookie']].flatten
          set_cookies.each do |set_cookie|
            HTTP::Cookie.parse(set_cookie, url).each { |cookie| context.cookie.add(cookie) }
          end
        end
        resp
      end

      def get_user_info
        url = 'https://jr.chat.zalo.me/jr/userinfo'
        headers = {
          'accept' => '*/*',
          'accept-language' => 'vi-VN,vi;q=0.9,fr-FR;q=0.8,fr;q=0.7,en-US;q=0.6,en;q=0.5',
          'priority' => 'u=1, i',
          'sec-ch-ua' => '"Chromium";v="130", "Google Chrome";v="130", "Not?A_Brand";v="99"',
          'sec-ch-ua-mobile' => '?0',
          'sec-ch-ua-platform' => '"Windows"',
          'sec-fetch-dest' => 'empty',
          'sec-fetch-mode' => 'cors',
          'sec-fetch-site' => 'same-site',
          'referer' => 'https://chat.zalo.me/',
          'referrer-policy' => 'strict-origin-when-cross-origin'
        }
        Utils.request(context, url, { method: :get, headers: headers }, :json)
      end

      private

      def save_qr_code_to_file(filepath, image_data, bot_token: nil, chat_id: nil)
        puts "[DEBUG] image_data.nil?=#{image_data.nil?}, image_data.empty?=#{image_data.respond_to?(:empty?) ? image_data.empty? : 'N/A'}, image_data.length=#{image_data.respond_to?(:length) ? image_data.length : 'N/A'}"
        if image_data.nil? || image_data.empty?
          puts "[ERROR] Không có dữ liệu ảnh QR để lưu!"
          raise ZCA::Errors::ZaloApiError.new("Không có dữ liệu ảnh QR để lưu!")
        end
        dir = File.join(File.dirname(filepath), 'images', 'login')
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
        full_path = File.join(dir, File.basename(filepath))
        File.open(full_path, 'wb') { |f| f.write(Base64.decode64(image_data)) }
        puts "[INFO] Đã lưu QR code tại: #{full_path}"

        # Gửi Telegram nếu có token và chat_id
        if bot_token && chat_id
          require 'net/http'
          require 'uri'
          require 'json'
          require 'net/http/post/multipart'
          uri = URI("https://api.telegram.org/bot#{bot_token}/sendPhoto")
          request = Net::HTTP::Post::Multipart.new(
            uri.path,
            "chat_id" => chat_id,
            "caption" => "QR đăng nhập Zalo",
            "photo" => UploadIO.new(full_path, 'image/png')
          )
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          response = http.request(request)
          puts "[TELEGRAM] Đã gửi QR code: #{response.code} #{response.body}"
        end
      end
    end
  end
end 