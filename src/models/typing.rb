# frozen_string_literal: true

module ZCA
  module Models
    TTyping = Struct.new(:uid, :ts, :is_pc, keyword_init: true)
    TGroupTyping = Struct.new(:uid, :ts, :is_pc, :gid, keyword_init: true)

    class UserTyping
      attr_reader :type, :data, :thread_id, :is_self
      def initialize(data)
        @type = ThreadType::USER
        @data = data
        @thread_id = data.uid
        @is_self = false
      end
    end

    class GroupTyping
      attr_reader :type, :data, :thread_id, :is_self
      def initialize(data)
        @type = ThreadType::GROUP
        @data = data
        @thread_id = data.gid
        @is_self = false
      end
    end
    # Typing = UserTyping | GroupTyping (duck typing)
  end
end 