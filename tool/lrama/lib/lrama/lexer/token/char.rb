# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Lexer
    module Token
      class Char < Base
        # @rbs () -> void
        def validate
          validate_ascii_code_range
        end

        private

        # @rbs () -> void
        def validate_ascii_code_range
          unless s_value.ascii_only?
            errors << "Invalid character: `#{s_value}`. Only ASCII characters are allowed."
          end
        end
      end
    end
  end
end
