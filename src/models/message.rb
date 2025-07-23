# frozen_string_literal: true

module ZCA
  module Models
    module ThreadType
      USER = 0
      GROUP = 1
    end

    TAttachmentContent = Struct.new(
      :title, :description, :href, :thumb, :childnumber, :action, :params, :type,
      keyword_init: true
    )

    TOtherContent = Struct.new(:extra, keyword_init: true) # flexible hash

    TQuote = Struct.new(
      :owner_id, :cli_msg_id, :global_msg_id, :cli_msg_type, :ts, :msg, :attach, :from_d, :ttl,
      keyword_init: true
    )

    TMention = Struct.new(:uid, :pos, :len, :type, keyword_init: true)

    TMessage = Struct.new(
      :action_id, :msg_id, :cli_msg_id, :msg_type, :uid_from, :id_to, :d_name, :ts, :status, :content, :notify, :ttl,
      :user_id, :uin, :top_out, :top_out_time_out, :top_out_impr_time_out, :property_ext, :params_ext, :cmd, :st, :at,
      :real_msg_id, :quote,
      keyword_init: true
    )

    TGroupMessage = Struct.new(
      :action_id, :msg_id, :cli_msg_id, :msg_type, :uid_from, :id_to, :d_name, :ts, :status, :content, :notify, :ttl,
      :user_id, :uin, :top_out, :top_out_time_out, :top_out_impr_time_out, :property_ext, :params_ext, :cmd, :st, :at,
      :real_msg_id, :quote, :mentions,
      keyword_init: true
    )

    class UserMessage
      attr_reader :type, :data, :thread_id, :is_self
      def initialize(uid, data)
        @type = ThreadType::USER
        @data = data
        @thread_id = data.uid_from == '0' ? data.id_to : data.uid_from
        @is_self = data.uid_from == '0'
        data.id_to = uid if data.id_to == '0'
        data.uid_from = uid if data.uid_from == '0'
      end
    end

    class GroupMessage
      attr_reader :type, :data, :thread_id, :is_self
      def initialize(uid, data)
        @type = ThreadType::GROUP
        @data = data
        @thread_id = data.id_to
        @is_self = data.uid_from == '0'
        data.uid_from = uid if data.uid_from == '0'
      end
    end

    # Message = UserMessage | GroupMessage (dùng duck typing Ruby)
  end
end 