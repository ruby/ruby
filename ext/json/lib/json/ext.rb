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
    sort_keys_proc = ->(hash) { hash.sort.to_h }
    if defined?(::Ractor) && Ractor.respond_to?(:shareable_lambda)
      sort_keys_proc = Ractor.shareable_lambda(&sort_keys_proc)
    end
    generator::State.default_sort_keys_proc = sort_keys_proc
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
