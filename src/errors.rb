# frozen_string_literal: true

module ZCA
  module Errors
    class ZaloApiError < StandardError
      attr_reader :code
      def initialize(message, code = nil)
        super(message)
        @code = code
      end
    end
    # Có thể mở rộng thêm các lỗi khác tại đây
  end
end 