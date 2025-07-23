# frozen_string_literal: true

module ZCA
  module Models
    module GroupEventType
      JOIN_REQUEST = 0
      JOIN = 1
      LEAVE = 2
      REMOVE_MEMBER = 3
      BLOCK_MEMBER = 4
      UPDATE_SETTING = 5
      UPDATE = 6
      NEW_LINK = 7
      ADD_ADMIN = 8
      REMOVE_ADMIN = 9
      NEW_PIN_TOPIC = 10
      UPDATE_PIN_TOPIC = 11
      REORDER_PIN_TOPIC = 12
      UPDATE_BOARD = 13
      REMOVE_BOARD = 14
      UPDATE_TOPIC = 15
      UNPIN_TOPIC = 16
      REMOVE_TOPIC = 17
      ACCEPT_REMIND = 18
      REJECT_REMIND = 19
      REMIND_TOPIC = 20
      UPDATE_AVATAR = 21
      UNKNOWN = 22
    end

    Member = Struct.new(:id, :d_name, :avatar, :type, :avatar_25, keyword_init: true)
    GroupSetting = Struct.new(
      :block_name, :sign_admin_msg, :add_member_only, :set_topic_only, :enable_msg_history, :join_appr,
      :lock_create_post, :lock_create_poll, :lock_send_msg, :lock_view_member, :bann_feature, :dirty_media, :ban_duration,
      keyword_init: true
    )
    GroupTopic = Struct.new(
      :type, :color, :emoji, :start_time, :duration, :params, :id, :creator_id, :create_time, :editor_id, :edit_time, :repeat, :action,
      keyword_init: true
    )
    GroupInfo = Struct.new(:group_link, :link_expired_time, :extra, keyword_init: true)
    GroupExtraData = Struct.new(:feature_id, :field, :extra, keyword_init: true)

    TGroupEventBase = Struct.new(
      :sub_type, :group_id, :creator_id, :group_name, :source_id, :update_members, :group_setting, :group_topic,
      :info, :extra_data, :time, :avt, :full_avt, :is_add, :hide_group_info, :version, :group_type, :client_id, :error_map, :e2ee,
      keyword_init: true
    )
    TGroupEventJoinRequest = Struct.new(:uids, :total_pending, :group_id, :time, keyword_init: true)
    TGroupEventPinTopic = Struct.new(:old_board_version, :board_version, :topic, :actor_id, :group_id, keyword_init: true)
    TGroupEventReorderPinTopic = Struct.new(:old_board_version, :actor_id, :topics, :group_id, :board_version, :topic, keyword_init: true)
    TGroupEventBoard = Struct.new(
      :source_id, :group_name, :group_topic, :group_id, :creator_id, :sub_type, :update_members, :group_setting, :info, :extra_data,
      :time, :avt, :full_avt, :is_add, :hide_group_info, :version, :group_type,
      keyword_init: true
    )
    TGroupEventRemindRespond = Struct.new(:topic_id, :update_members, :group_id, :time, keyword_init: true)
    TGroupEventRemindTopic = Struct.new(
      :msg, :editor_id, :color, :emoji, :creator_id, :edit_time, :type, :duration, :group_id, :create_time, :repeat, :start_time, :time, :remind_type,
      keyword_init: true
    )

    def self.initialize_group_event(uid, data, type)
      thread_id = data.respond_to?(:group_id) ? data.group_id : (data.respond_to?(:group_id) ? data.group_id : nil)
      case type
      when GroupEventType::JOIN_REQUEST
        {
          type: type,
          data: data,
          thread_id: thread_id,
          is_self: false
        }
      when GroupEventType::NEW_PIN_TOPIC, GroupEventType::UNPIN_TOPIC, GroupEventType::UPDATE_PIN_TOPIC
        {
          type: type,
          data: data,
          thread_id: thread_id,
          is_self: data.actor_id == uid
        }
      when GroupEventType::REORDER_PIN_TOPIC
        {
          type: type,
          data: data,
          thread_id: thread_id,
          is_self: data.actor_id == uid
        }
      when GroupEventType::UPDATE_BOARD, GroupEventType::REMOVE_BOARD
        {
          type: type,
          data: data,
          thread_id: thread_id,
          is_self: data.source_id == uid
        }
      when GroupEventType::ACCEPT_REMIND, GroupEventType::REJECT_REMIND
        {
          type: type,
          data: data,
          thread_id: thread_id,
          is_self: data.update_members&.include?(uid)
        }
      when GroupEventType::REMIND_TOPIC
        {
          type: type,
          data: data,
          thread_id: thread_id,
          is_self: data.creator_id == uid
        }
      else
        base_data = data
        is_self =
          if base_data.respond_to?(:update_members) && base_data.update_members
            base_data.update_members.any? { |m| m.respond_to?(:id) ? m.id == uid : m == uid }
          elsif base_data.respond_to?(:source_id)
            base_data.source_id == uid
          else
            false
          end
        {
          type: type,
          data: base_data,
          thread_id: thread_id,
          is_self: is_self
        }
      end
    end
  end
end 