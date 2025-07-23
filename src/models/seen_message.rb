# frozen_string_literal: true

module ZCA
  module Models
    TUserSeenMessage = Struct.new(:id_to, :msg_id, :real_msg_id, keyword_init: true)
    TGroupSeenMessage = Struct.new(:msg_id, :group_id, :seen_uids, keyword_init: true)

    class UserSeenMessage
      attr_reader :type, :data, :thread_id, :is_self
      def initialize(data)
        @type = ThreadType::USER
        @data = data
        @thread_id = data.id_to
        @is_self = false
      end
    end

    class GroupSeenMessage
      attr_reader :type, :data, :thread_id, :is_self
      def initialize(uid, data)
        @type = ThreadType::GROUP
        @data = data
        @thread_id = data.group_id
        @is_self = data.seen_uids.include?(uid)
      end
    end
    # SeenMessage = UserSeenMessage | GroupSeenMessage (duck typing)
  end
end 