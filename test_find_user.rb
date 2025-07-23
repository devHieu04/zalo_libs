require_relative 'src/context'
require_relative 'src/apis/find_user'
require_relative 'src/apis/login'

# 1. Tạo context với cookie, imei, user_agent
imei = "9b96b0e4-7336-4428-be95-5e21584b944b-ce69b851c4edc7eebfb3998aa94a7157"
user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
cookie_path = "/Users/hieu.nguyen/Documents/personal/zalo_libs/chat.zalo.me_23-07-2025.json" # hoặc file cookie bạn đã lưu

context = ZCA::Context.login_with_cookie(
  cookie_path: cookie_path,
  imei: imei,
  user_agent: user_agent
)
api = ZCA::API::FindUser.new(context)
user_info = api.find_user("0349582687")
puts user_info.inspect