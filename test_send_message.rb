# frozen_string_literal: true

require_relative 'src/context'
require_relative 'src/apis/send_message'
require_relative 'src/apis/find_user'
require_relative 'src/apis/login'
require_relative 'src/models/send_message'
require 'json'
require 'pry'

# 1. Tạo context với cookie, imei, user_agent
imei = "9b96b0e4-7336-4428-be95-5e21584b944b-ce69b851c4edc7eebfb3998aa94a7157"
user_agent = "Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Mobile Safari/537.36"
cookie_path = "/Users/hieu.nguyen/Documents/personal/zalo_libs/chat.zalo.me_23-07-2025.json" # hoặc file cookie bạn đã lưu

context = ZCA::Context.create_context(imei: imei)
json = File.read(cookie_path)
context.cookie = ZCA::Cookie::CookieJar.from_json(json)
context.user_agent = user_agent

# Thiết lập settings.features.sharefile mặc định để hỗ trợ upload file
context.settings = OpenStruct.new(
  features: OpenStruct.new(
    sharefile: OpenStruct.new(
      chunk_size_file: 2 * 1024 * 1024,
      max_file: 10,
      max_size_share_file_v3: 20, # MB
      restricted_ext_file: []
    )
  )
)

api = ZCA::API::Login.new(context)
result = api.login(encrypt_params: false)



# === BỔ SUNG: Gọi get_server_info để lấy thông tin chuẩn từ server ===
server_info = api.get_server_info(encrypt_params: false)
puts "Server info: #{server_info.inspect}"
if server_info.is_a?(Hash)
  context.API_TYPE ẽ= server_info['api_type'] if server_info['api_type']
  context.API_VERSION = server_info['api_version'] if server_info['api_version']
  context.zpw_service_map = server_info['zpw_service_map_v3'] if server_info['zpw_service_map_v3']
end
# === END BỔ SUNG ===

# === BỔ SUNG: Gán secret_key và zpw_service_map vào context sau login (nếu chưa có) ===
if result.is_a?(Hash)
  data = result['data'] || result
  context.secret_key = data['zpw_enk'] if data['zpw_enk']
  context.zpw_service_map = data['zpw_service_map_v3'] if data['zpw_service_map_v3']
end
# === END BỔ SUNG ===

api = ZCA::API::FindUser.new(context)
user_info = api.find_user("0349582687")

# === TEST GỬI TIN NHẮN TEXT ĐƠN GIẢN ===
send_api = ZCA::API::SendMessage.new(context)
puts "\n--- Gửi tin nhắn text đơn giản ---"
msg = "Hello from Ruby SDK!"
res = send_api.send_message(msg, user_info['uid'], :user)
puts res.inspect

# # === TEST GỬI TIN NHẮN CÓ MENTIONS, STYLES, URGENCY, TTL ===
# puts "\n--- Gửi tin nhắn nâng cao ---"
# message = ZCA::Models::MessageContent.new(
#   msg: "@user Xin chào! Đây là tin nhắn có style.",
#   mentions: [ZCA::Models::Mention.new(pos: 0, uid: user_info['uid'], len: 5)],
#   styles: [ZCA::Models::Style.new(start: 0, len: 5, st: ZCA::Models::TextStyle::BOLD)],
#   urgency: ZCA::Models::Urgency::URGENT, # Urgent
#   ttl: 60 # 60 giây
# )
# res = send_api.send_message(message, user_info['uid'], :user)
# puts res.inspect

# === TEST GỬI FILE/ATTACHMENT (nếu có file mẫu) ===
file_path = "/Users/hieu.nguyen/Documents/personal/zalo_libs/Screenshot 2025-07-24 at 13.21.59.png"
if File.exist?(file_path)
  puts "\n--- Gửi file ảnh ---"
  puts "API_TYPE: #{context.API_TYPE}, API_VERSION: #{context.API_VERSION}"
  message = ZCA::Models::MessageContent.new(
    msg: "",
    attachments: [file_path],
    ttl: 120
  )
  res = send_api.send_message(message, user_info['uid'], :user)
  puts res.inspect
end

puts "\nHoàn thành test gửi tin nhắn!" 