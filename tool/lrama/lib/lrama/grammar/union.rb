# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Grammar
    class Union
      attr_reader :code #: Grammar::Code::NoReferenceCode
      attr_reader :lineno #: Integer

      # @rbs (code: Grammar::Code::NoReferenceCode, lineno: Integer) -> void
      def initialize(code:, lineno:)
        @code = code
        @lineno = lineno
      end

      # @rbs () -> String
      def braces_less_code
        # Braces is already removed by lexer
        code.s_value
      end
    end
  end
end
