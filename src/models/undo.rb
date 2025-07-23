# frozen_string_literal: true

module ZCA
  module Models
    TUndoContent = Struct.new(:global_msg_id, :cli_msg_id, :delete_msg, :src_id, :dest_id, keyword_init: true)
    TUndo = Struct.new(
      :action_id, :msg_id, :cli_msg_id, :msg_type, :uid_from, :id_to, :d_name, :ts, :status, :content, :notify, :ttl,
      :user_id, :uin, :cmd, :st, :at, :real_msg_id,
      keyword_init: true
    )

    class Undo
      attr_reader :data, :thread_id, :is_self, :is_group
      def initialize(uid, data, is_group)
        @data = data
        @thread_id = is_group || data.uid_from == '0' ? data.id_to : data.uid_from
        @is_self = data.uid_from == '0'
        @is_group = is_group
        data.id_to = uid if data.id_to == '0'
        data.uid_from = uid if data.uid_from == '0'
      end
    end
  end
end 