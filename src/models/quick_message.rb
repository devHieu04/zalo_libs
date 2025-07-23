# frozen_string_literal: true

module ZCA
  module Models
    QuickMessageMessage = Struct.new(:title, :params, keyword_init: true)
    QuickMessage = Struct.new(
      :id, :keyword, :type, :created_time, :last_modified, :message, :media,
      keyword_init: true
    )
  end
end 