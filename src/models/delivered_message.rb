# frozen_string_literal: true

module ZCA
  module Models
    TDeliveredMessage = Struct.new(:msg_id, :seen, :delivered_uids, :seen_uids, :real_msg_id, :m_s_ts, keyword_init: true)
    TGroupDeliveredMessage = Struct.new(:msg_id, :seen, :delivered_uids, :seen_uids, :real_msg_id, :m_s_ts, :group_id, keyword_init: true)

    class UserDeliveredMessage
      attr_reader :type, :data, :thread_id, :is_self
      def initialize(data)
        @type = ThreadType::USER
        @data = data
        @thread_id = data.delivered_uids[0]
        @is_self = false
      end
    end

    class GroupDeliveredMessage
      attr_reader :type, :data, :thread_id, :is_self
      def initialize(uid, data)
        @type = ThreadType::GROUP
        @data = data
        @thread_id = data.group_id
        @is_self = data.delivered_uids.include?(uid)
      end
    end
    # DeliveredMessage = UserDeliveredMessage | GroupDeliveredMessage (duck typing)
  end
end 