# frozen_string_literal: true

module ZCA
  module Models
    module ThreadType
      USER = 0
      GROUP = 1
    end

    module DestType
      USER = 3
      PAGE = 5
    end

    module ReminderRepeatMode
      NONE = 0
      DAILY = 1
      WEEKLY = 2
      MONTHLY = 3
    end

    module Gender
      MALE = 0
      FEMALE = 1
    end

    module BoardType
      NOTE = 1
      PINNED_MESSAGE = 2
      POLL = 3
    end
  end
end 