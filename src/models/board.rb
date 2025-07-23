# frozen_string_literal: true

module ZCA
  module Models
    PollOptions = Struct.new(:content, :votes, :voted, :voters, :option_id, keyword_init: true)
    PollDetail = Struct.new(
      :creator, :question, :options, :joined, :closed, :poll_id, :allow_multi_choices, :allow_add_new_option,
      :is_anonymous, :poll_type, :created_time, :updated_time, :expired_time, :is_hide_vote_preview, :num_vote,
      keyword_init: true
    )
    NoteDetail = Struct.new(
      :id, :type, :color, :emoji, :start_time, :duration, :params, :creator_id, :editor_id, :create_time, :edit_time, :repeat,
      keyword_init: true
    )
    PinnedMessageDetail = Struct.new(
      :id, :type, :color, :emoji, :start_time, :duration, :params, :creator_id, :editor_id, :create_time, :edit_time, :repeat,
      keyword_init: true
    )
  end
end 