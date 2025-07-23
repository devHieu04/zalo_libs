# frozen_string_literal: true

module ZCA
  module Models
    ReminderUserParams = Struct.new(:title, :set_title, keyword_init: true)
    ReminderUser = Struct.new(
      :creator_uid, :to_uid, :emoji, :color, :reminder_id, :create_time, :repeat, :start_time, :edit_time, :end_time, :params, :type,
      keyword_init: true
    )
    ReminderGroupParams = Struct.new(:title, :set_title, keyword_init: true)
    ReminderGroup = Struct.new(
      :id, :type, :color, :emoji, :start_time, :duration, :params, :creator_id, :editor_id, :create_time, :edit_time, :repeat,
      keyword_init: true
    )
  end
end 