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

      def valid_encoding?(str) # :nodoc:
        str.ascii_only? || (str.encoding == Encoding::UTF_8 && str.valid_encoding?)
      end

      def coerce_key(key, as_json) # :nodoc:
        as_json_called = false

        unless String === key || Symbol === key
          key = as_json.call(key, true)
          as_json_called = true
        end

        if Symbol === key
          key = key.to_s
        end

        unless String === key
          raise GeneratorError.new("#{key.class} not allowed as object key in JSON", key)
        end

        unless valid_encoding?(key)
          if as_json_called
            raise GeneratorError.new("source sequence is illegal/malformed utf-8", key)
          end

          key = as_json.call(key, true)
          unless String === key
            raise GeneratorError.new("#{key.class} not allowed as object key in JSON", key)
          end

          unless Ext.valid_encoding?(key)
            raise GeneratorError.new("source sequence is illegal/malformed utf-8", key)
          end
        end

        key
      end

      def on_duplicate_key(hash, as_json)
        set = {}
        hash.each_key do |key|
          key = coerce_key(key, as_json)
          if set[key]
            raise GeneratorError.new("detected duplicate key #{key.inspect}", key)
          else
            set[key] = true
          end
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
    generator::State.rfc8785_number_formatter_proc = shareable_lambda(->(num) {
      if Integer === num
        if num > Float::MAX || num < -Float::MAX
          raise GeneratorError.new("Integer out of range for RFC 8785", num)
        end
        num = num.to_f
      end
      if num.zero?
        "0"
      else
        if num < 0
          num, sign = -num, '-'
        end
        native_rep = num.to_s
        decimal, exponential = native_rep.split('e')
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

    generator::State.rfc8785_sort_keys_proc = shareable_lambda(->(hash, as_json) {
      converted = if as_json
        hash.transform_keys { |k| Ext.coerce_key(k, as_json) }
      else
        hash.transform_keys(&:to_s)
      end

      if converted.size < hash.size
        Ext.on_duplicate_key(hash, as_json)
      end

      converted.sort_by { |k,| k.encode(Encoding::UTF_16) }.to_h
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
