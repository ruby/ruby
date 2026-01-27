# frozen_string_literal: true
# :markup: markdown

require_relative "../ripper"

module Prism
  module Translation
    class Ripper
      class Lexer < Ripper # :nodoc:
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

          # Instances are frozen and there are only a handful of them so we cache them here.
          STATES = Hash.new { |h,k| h[k] = State.new(k) }

          def self.cached(i)
            STATES[i]
          end
        end

        class Elem
          attr_accessor :pos, :event, :tok, :state, :message

          def initialize(pos, event, tok, state, message = nil)
            @pos = pos
            @event = event
            @tok = tok
            @state = State.cached(state)
            @message = message
          end

          def [](index)
            case index
            when 0, :pos
              @pos
            when 1, :event
              @event
            when 2, :tok
              @tok
            when 3, :state
              @state
            when 4, :message
              @message
            else
              nil
            end
          end

          def inspect
            "#<#{self.class}: #{event}@#{pos[0]}:#{pos[1]}:#{state}: #{tok.inspect}#{": " if message}#{message}>"
          end

          alias to_s inspect

          def pretty_print(q)
            q.group(2, "#<#{self.class}:", ">") {
              q.breakable
              q.text("#{event}@#{pos[0]}:#{pos[1]}")
              q.breakable
              state.pretty_print(q)
              q.breakable
              q.text("token: ")
              tok.pretty_print(q)
              if message
                q.breakable
                q.text("message: ")
                q.text(message)
              end
            }
          end

          def to_a
            if @message
              [@pos, @event, @tok, @state, @message]
            else
              [@pos, @event, @tok, @state]
            end
          end
        end

        # Pretty much just the same as Prism.lex_compat.
        def lex(raise_errors: false)
          Ripper.lex(@source, filename, lineno, raise_errors: raise_errors)
        end

        # Returns the lex_compat result wrapped in `Elem`. Errors are omitted.
        # Since ripper is a streaming parser, tokens are expected to be emitted in the order
        # that the parser encounters them. This is not implemented.
        def parse(...)
          lex(...).map do |position, event, token, state|
            Elem.new(position, event, token, state.to_int)
          end
        end

        # Similar to parse but ripper sorts the elements by position in the source. Also
        # includes errors. Since prism does error recovery, in cases of syntax errors
        # the result may differ greatly compared to ripper.
        def scan(...)
          parse(...)
        end

        # :startdoc:
      end
    end
  end
end
