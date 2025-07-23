# frozen_string_literal: true

require_relative 'src/context'
require_relative 'src/apis/base'
require_relative 'src/apis/login'
require_relative 'src/apis/login_qr'
require 'json'
require 'pry'

# Khởi tạo context mẫu
context = ZCA::Context.create_context(imei: '')

puts 'Chọn phương thức đăng nhập:'
puts '1. Đăng nhập bằng QR code'
puts '2. Đăng nhập thường (API)'
puts '3. Đăng nhập bằng file cookie (cookies.json)'
print 'Lựa chọn (1/2/3): '
mode = gets.strip

if mode == '3'
  print 'Nhập đường dẫn file cookie (cookies.json): '
  cookie_path = gets.strip
  unless File.exist?(cookie_path)
    puts 'File cookie không tồn tại!'
    exit 1
  end
  print 'Nhập imei thiết bị (bắt buộc, phải giống imei đã dùng khi lưu cookie): '
  imei = gets.strip
  if imei.empty?
    puts 'IMEI là bắt buộc khi login bằng cookie!'
    exit 1
  end
  context = ZCA::Context.create_context(imei: imei)
  json = File.read(cookie_path)
  context.cookie = ZCA::Cookie::CookieJar.from_json(json)
  print 'Chọn API: 1. QR  2. Thường (Enter để mặc định QR): '
  api_mode = gets.strip
  if api_mode == '2'
    api = ZCA::API::Login.new(context)
    begin
      result = api.login(encrypt_params: false)
      # Nếu kết quả là chuỗi, parse thành JSON
      if result.is_a?(String)
        begin
          result = JSON.parse(result)
        rescue
          # Nếu không parse được, giữ nguyên
        end
      end
      if result.is_a?(Hash) && result['error_code'] == 0
        puts 'Đăng nhập API bằng cookie thành công!'
      else
        puts 'Đăng nhập API bằng cookie thất bại.'
      end
    rescue => e
      puts "Lỗi: #{e.message}"
    end
  else
    api = ZCA::API::LoginQR.new(context)
    user_info = api.send(:get_user_info)
    user_info = user_info.is_a?(HTTParty::Response) ? user_info.parsed_response : user_info
    puts "[DEBUG] user_info: #{user_info.inspect}"
    if user_info && user_info['data'] && user_info['data']['logged']
      puts 'Đăng nhập QR bằng cookie thành công!'
      puts "Thông tin user: #{user_info['data']['info'].inspect}"
      puts "Cookies: #{context.cookie.to_json}"
    else
      puts 'Cookie không hợp lệ hoặc đã hết hạn. Vui lòng đăng nhập lại bằng QR hoặc API.'
    end
  end
  exit
end

if mode == '1'
  print 'Nhập user agent trình duyệt (hoặc Enter để dùng mặc định): '
  user_agent = gets.strip
  user_agent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' if user_agent.empty?
  print 'Nhập tên file QR code (vd: qr.png, Enter để mặc định): '
  qr_filename = gets.strip
  qr_filename = 'qr.png' if qr_filename.empty?
  qr_path = File.join('images', 'login', qr_filename)
  print 'Nhập Telegram bot token (Enter để bỏ qua): '
  bot_token = gets.strip
  bot_token = nil if bot_token.empty?
  print 'Nhập Telegram chat_id (Enter để bỏ qua): '
  chat_id = gets.strip
  chat_id = nil if chat_id.empty?
  context = ZCA::Context.create_context
  api = ZCA::API::LoginQR.new(context)
  puts 'Đang tạo QR code...'
  result = nil
  api.login_qr(user_agent: user_agent, qr_path: qr_path) do |event|
    case event[:type]
    when ZCA::API::LoginQRCallbackEventType::QRCodeGenerated
      event[:actions][:save_to_file].call(qr_path, bot_token: bot_token, chat_id: chat_id)
      puts "Đã tạo QR code, lưu tại: #{qr_path}"
      puts 'Vui lòng quét QR code để đăng nhập.'
    when ZCA::API::LoginQRCallbackEventType::QRCodeExpired
      puts 'QR code đã hết hạn. Đang tạo lại...'
    when ZCA::API::LoginQRCallbackEventType::QRCodeScanned
      puts "Đã quét QR code. Đang xác nhận trên điện thoại..."
    when ZCA::API::LoginQRCallbackEventType::QRCodeDeclined
      puts 'QR code bị từ chối. Đang tạo lại...'
    end
  end
  # Sau khi login QR, callback lại login bằng cookies để đảm bảo context hợp lệ như JS SDK
  user_info = api.send(:get_user_info)
  user_info = user_info.is_a?(HTTParty::Response) ? user_info.parsed_response : user_info
  puts "[DEBUG] user_info: #{user_info.inspect}"
  if user_info && user_info['data'] && user_info['data']['error_code'] == 0
    puts 'Đăng nhập QR thành công!'
    puts "Thông tin user: #{user_info['data']['info'].inspect}"
    puts "Cookies: #{context.cookie.to_json}"
    File.write('cookies.json', context.cookie.to_json)
    puts 'Đã lưu cookies vào cookies.json.'
  else
    puts 'Đăng nhập thất bại hoặc bị hủy.'
  end
  exit
end

if mode == '2'
  context = ZCA::Context.create_context
  api = ZCA::API::Login.new(context)
  begin
    result = api.login(encrypt_params: false)
    # Nếu kết quả là chuỗi, parse thành JSON
    if result.is_a?(String)
      begin
        result = JSON.parse(result)
      rescue
        # Nếu không parse được, giữ nguyên
      end
    end
    if result.is_a?(Hash) && result['error_code'] == 0
      puts 'Đăng nhập API thành công!'
      puts result.inspect
      File.write('cookies.json', context.cookie.to_json)
      puts 'Đã lưu cookies vào cookies.json.'
    else
      puts 'Đăng nhập API thất bại.'
    end
  rescue => e
    puts "Lỗi: #{e.message}"
  end
  exit
end 