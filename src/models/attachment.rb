# frozen_string_literal: true

module ZCA
  module Models
    # AttachmentSource: có thể là string (đường dẫn file) hoặc object với data, filename, metadata
    AttachmentMetadata = Struct.new(:total_size, :width, :height, keyword_init: true)
    AttachmentObject = Struct.new(:data, :filename, :metadata, keyword_init: true)
    # AttachmentSource: String (file path) hoặc AttachmentObject
    # Dùng duck typing Ruby: chỉ cần kiểm tra respond_to?(:data) hoặc là String
  end
end 