# frozen_string_literal: true
# :markup: markdown

require_relative "../ripper"

module Prism
  module Translation
    class Ripper
      class Lexer # :nodoc:
        # :stopdoc:
        class State

          attr_reader :to_int, :to_s

          def initialize(i)
            @to_int = i
            @to_s = Ripper.lex_state_name(i)
            freeze
          end

          def [](index)
            case index
            when 0, :to_int
              @to_int
            when 1, :to_s
              @to_s
            else
              nil
            end
          end

          alias to_i to_int
          alias inspect to_s
          def pretty_print(q) q.text(to_s) end
          def ==(i) super or to_int == i end
          def &(i) self.class.new(to_int & i) end
          def |(i) self.class.new(to_int | i) end
          def allbits?(i) to_int.allbits?(i) end
          def anybits?(i) to_int.anybits?(i) end
          def nobits?(i) to_int.nobits?(i) end
        end
        # :startdoc:
      end
    end
  end
end
