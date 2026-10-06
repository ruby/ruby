# frozen_string_literal: true

require 'json/common'

module JSON
  # This module holds all the modules/classes that implement JSON's
  # functionality as C extensions.
  module Ext
    class Parser
      class << self
        def parse(...)
          new(...).parse
        end
        alias_method :parse, :parse # Allow redefinition by extensions
      end

      def initialize(source, opts = nil)
        @source = source
        @config = Config.new(opts)
      end

      def source
        @source.dup
      end

      def parse
        @config.parse(@source)
      end
    end

    class << self
      if defined?(::Ractor) && Ractor.respond_to?(:shareable_lambda)
        def shareable_lambda(block) # :nodoc:
          Ractor.shareable_lambda(&block)
        end
      else
        def shareable_lambda(block) # :nodoc:
          block
        end
      end
    end

    require 'json/ext/parser'
    Ext::Parser::Config = Ext::ParserConfig
    JSON.parser = Ext::Parser

    generator = if RUBY_ENGINE == 'truffleruby'
      require 'json/truffle_ruby/generator'
      JSON::TruffleRuby::Generator
    else
      require 'json/ext/generator'
      Generator
    end

    # The default proc used when the +sort_keys+ generation option is +true+.
    # It returns a new hash with the entries sorted by their keys.
    generator::State.default_sort_keys_proc = shareable_lambda(->(hash) {
      hash.sort.to_h
    })

    # Directly lifted from Gregg Kellogg's json-canonicalization
    generator::State.rfc8785_number_formater_proc = shareable_lambda(->(num) {
      if num.zero?
        "0"
      else
        if num < 0
          num, sign = -num, '-'
        end
        native_rep = "%.15E" % num
        decimal, exponential = native_rep.split('E')
        exp_val = exponential.to_i
        exponential = exp_val > 0 ? ('+' + exp_val.to_s) : exp_val.to_s

        integral, fractional = decimal.split('.')
        fractional = fractional.sub(/0+$/, '')  # Remove trailing zeros

        if exp_val > 0 && exp_val < 21
          while exp_val > 0
            integral += fractional.to_s[0] || '0'
            fractional = fractional.to_s[1..-1]
            exp_val -= 1
          end
          exponential = nil
        elsif exp_val == 0
          exponential = nil
        elsif exp_val < 0 && exp_val > -7
          # Small numbers are shown as 0.etc with e-6 as lower limit
          fractional, integral, exponential = integral + fractional.to_s, '0', nil
          fractional = ("0" * (-exp_val - 1)) + fractional
        end

        fractional = nil if fractional.to_s.empty?
        sign.to_s + integral + (fractional ? ".#{fractional}" : '') + (exponential ? "e#{exponential}" : '')
      end
    })

    generator::State.rfc8785_sort_keys_proc = shareable_lambda(->(hash) {
      hash.sort_by { |k| k.to_s.encode(Encoding::UTF_16) }.to_h
    })

    JSON.generator = generator
  end

  if defined?(ResumableParser) # Not yet available on JRuby
    class ResumableParser
      # Returns whether the parser is entirely done: no unconsumed bytes in
      # the buffer, no document under construction and no parsed value
      # awaiting retrieval.
      #
      # The main use case is detecting a truncated stream once the input is
      # exhausted:
      #
      #   loop do
      #     begin
      #       parser << socket.readpartial(4096)
      #     rescue EOFError
      #       break
      #     end
      #     while parser.parse
      #       process(parser.value)
      #     end
      #   end
      #   warn "stream was truncated" unless parser.empty?
      def empty?
        eos? && !partial_value? && !value?
      end
    end
  end
end
