require_relative 'src/context'
require_relative 'src/apis/find_user'
require_relative 'src/apis/login'

# 1. Tạo context với cookie, imei, user_agent
imei = "9b96b0e4-7336-4428-be95-5e21584b944b-ce69b851c4edc7eebfb3998aa94a7157"
user_agent = "Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Mobile Safari/537.36"
cookie_path = "/Users/hieu.nguyen/Documents/personal/zalo_libs/chat.zalo.me_23-07-2025.json" # hoặc file cookie bạn đã lưu

context = ZCA::Context.create_context(imei: imei)
json = File.read(cookie_path)
context.cookie = ZCA::Cookie::CookieJar.from_json(json)
context.user_agent = user_agent

api = ZCA::API::Login.new(context)
result = api.login(encrypt_params: false)

# === BỔ SUNG: Gán secret_key và zpw_service_map vào context sau login ===
if result.is_a?(Hash)
  # JS: ctx.secretKey = loginData.data.zpw_enk; ctx.zpwServiceMap = loginData.data.zpw_service_map_v3
  data = result['data'] || result
  context.secret_key = data['zpw_enk'] if data['zpw_enk']
  context.zpw_service_map = data['zpw_service_map_v3'] if data['zpw_service_map_v3']
end
# === END BỔ SUNG ===

api = ZCA::API::FindUser.new(context)
user_info = api.find_user("0349582687")
puts user_info.inspect
