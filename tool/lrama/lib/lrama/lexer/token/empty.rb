# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Lexer
    module Token
      class Empty < Base
        def initialize(location: nil)
          super(s_value: '%empty', location: location)
        end
      end
    end
  end
end
