# frozen_string_literal: true

module Prism
  module Translation
    class Ripper
      class Filter # :nodoc:
        # :stopdoc:
        def initialize(src, filename = '-', lineno = 1)
          @__lexer = Lexer.new(src, filename, lineno)
          @__line = nil
          @__col = nil
          @__state = nil
        end

        def filename
          @__lexer.filename
        end

        def lineno
          @__line
        end

        def column
          @__col
        end

        def state
          @__state
        end

        def parse(init = nil)
          data = init
          @__lexer.lex.each do |pos, event, tok, state|
            @__line, @__col = *pos
            @__state = state
            data = if respond_to?(event, true)
                  then __send__(event, tok, data)
                  else on_default(event, tok, data)
                  end
          end
          data
        end

        private

        def on_default(event, token, data)
          data
        end
        # :startdoc:
      end
    end
  end
end
