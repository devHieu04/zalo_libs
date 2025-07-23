# frozen_string_literal: true

module ZCA
  module Models
    module FriendEventType
      ADD = 0
      REMOVE = 1
      REQUEST = 2
      UNDO_REQUEST = 3
      REJECT_REQUEST = 4
      SEEN_FRIEND_REQUEST = 5
      BLOCK = 6
      UNBLOCK = 7
      BLOCK_CALL = 8
      UNBLOCK_CALL = 9
      PIN_UNPIN = 10
      PIN_CREATE = 11
      UNKNOWN = 12
    end

    # TFriendEventBase = String
    TFriendEventRejectUndo = Struct.new(:to_uid, :from_uid, keyword_init: true)
    TFriendEventRequest = Struct.new(:to_uid, :from_uid, :src, :message, keyword_init: true)
    # TFriendEventSeenRequest = Array[String]
    TFriendEventPinCreateTopicParams = Struct.new(:sender_uid, :sender_name, :client_msg_id, :global_msg_id, :msg_type, :title, keyword_init: true)
    TFriendEventPinTopic = Struct.new(:topic_id, :topic_type, keyword_init: true)
    TFriendEventPinCreateTopic = Struct.new(
      :type, :color, :emoji, :start_time, :duration, :params, :id, :creator_id, :create_time, :editor_id, :edit_time, :repeat, :action,
      keyword_init: true
    )
    TFriendEventPinCreate = Struct.new(:old_topic, :topic, :actor_id, :old_version, :version, :conversation_id, keyword_init: true)
    TFriendEventPinUnpin = Struct.new(:topic, :actor_id, :old_version, :version, :conversation_id, keyword_init: true)

    def self.initialize_friend_event(uid, data, type)
      case type
      when FriendEventType::ADD, FriendEventType::REMOVE, FriendEventType::BLOCK, FriendEventType::UNBLOCK, FriendEventType::BLOCK_CALL, FriendEventType::UNBLOCK_CALL
        {
          type: type,
          data: data,
          thread_id: data,
          is_self: ![FriendEventType::ADD, FriendEventType::REMOVE].include?(type)
        }
      when FriendEventType::REJECT_REQUEST, FriendEventType::UNDO_REQUEST
        thread_id = data.to_uid
        {
          type: type,
          data: data,
          thread_id: thread_id,
          is_self: data.from_uid == uid
        }
      when FriendEventType::REQUEST
        thread_id = data.to_uid
        {
          type: type,
          data: data,
          thread_id: thread_id,
          is_self: data.from_uid == uid
        }
      when FriendEventType::SEEN_FRIEND_REQUEST
        {
          type: type,
          data: data,
          thread_id: uid,
          is_self: true
        }
      when FriendEventType::PIN_CREATE
        thread_id = data.conversation_id
        {
          type: type,
          data: data,
          thread_id: thread_id,
          is_self: data.actor_id == uid
        }
      when FriendEventType::PIN_UNPIN
        thread_id = data.conversation_id
        {
          type: type,
          data: data,
          thread_id: thread_id,
          is_self: data.actor_id == uid
        }
      else
        {
          type: FriendEventType::UNKNOWN,
          data: data.to_json,
          thread_id: '',
          is_self: false
        }
      end
    end
  end
end 