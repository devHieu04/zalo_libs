# frozen_string_literal: true

module ZCA
  module Models
    SendMessageResult = Struct.new(:msg_id, keyword_init: true)
    SendMessageResponse = Struct.new(:message, :attachment, keyword_init: true)
    SendMessageQuote = Struct.new(
      :content, :msg_type, :property_ext, :uid_from, :msg_id, :cli_msg_id, :ts, :ttl,
      keyword_init: true
    )

    module TextStyle
      BOLD = 'b'
      ITALIC = 'i'
      UNDERLINE = 'u'
      STRIKE_THROUGH = 's'
      RED = 'c_db342e'
      ORANGE = 'c_f27806'
      YELLOW = 'c_f7b503'
      GREEN = 'c_15a85f'
      SMALL = 'f_13'
      BIG = 'f_18'
      UNORDERED_LIST = 'lst_1'
      ORDERED_LIST = 'lst_2'
      INDENT = 'ind_$'
    end

    module Urgency
      DEFAULT = 0
      IMPORTANT = 1
      URGENT = 2
    end

    Style = Struct.new(:start, :len, :st, :indent_size, keyword_init: true)
    Mention = Struct.new(:pos, :uid, :len, keyword_init: true)

    MessageContent = Struct.new(
      :msg, :styles, :urgency, :quote, :mentions, :attachments, :ttl,
      keyword_init: true
    )

    SendType = Struct.new(:url, :body, :headers, keyword_init: true)
    UpthumbType = Struct.new(:hd_url, :client_file_id, :url, :file_id, keyword_init: true)

    # AttachmentData: flexible, dùng Hash hoặc Struct tuỳ trường hợp
    # Ví dụ:
    #   { file_type: 'image', body: ..., params: ... }
    #   { file_type: 'gif', body: ..., headers: ... }
  end
end 