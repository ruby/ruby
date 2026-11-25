# frozen_string_literal: true

module Gem
  ###
  # This module is used for safely loading YAML specs from a gem.  The
  # `safe_load` method defined on this module is specifically designed for
  # loading Gem specifications.  For loading other YAML safely, please see
  # Psych.safe_load

  module SafeYAML
    PERMITTED_CLASSES = %w[
      Symbol
      Time
      Date
      Gem::Dependency
      Gem::Platform
      Gem::Requirement
      Gem::Specification
      Gem::Version
      Gem::Version::Requirement
    ].freeze

    PERMITTED_SYMBOLS = %w[
      development
      runtime
    ].freeze

    MAX_ALIAS_EXPANSION = 100_000
    private_constant :MAX_ALIAS_EXPANSION

    @aliases_enabled = true
    def self.aliases_enabled=(value) # :nodoc:
      @aliases_enabled = !!value
    end

    def self.aliases_enabled? # :nodoc:
      @aliases_enabled
    end

    def self.safe_load(input)
      # Psych rejects legacy metadata bytes, so preserve them with the internal parser.
      if Gem.use_psych? && valid_encoding?(input)
        check_alias_expansion(input) if @aliases_enabled
        ::Psych.safe_load(input, permitted_classes: PERMITTED_CLASSES,
                                 permitted_symbols: PERMITTED_SYMBOLS, aliases: @aliases_enabled)
      else
        # Keeps the nil Psych returns, see Gem::YAMLSerializer.load
        ast = Gem::YAMLSerializer::Parser.new(input).parse
        Gem::YAMLSerializer::Builder.new(
          permitted_classes: PERMITTED_CLASSES,
          permitted_symbols: PERMITTED_SYMBOLS,
          aliases: aliases_enabled?
        ).build(ast)
      end
    end

    class << self
      alias_method :load, :safe_load
    end

    private_class_method def self.valid_encoding?(input)
      return true unless input.is_a?(String)

      input.dup.force_encoding(Encoding::UTF_8).valid_encoding?
    end

    # Psych.safe_load returns shared objects for aliases with no limit, and
    # flatten, to_ruby and to_yaml expand them later. Apply the same budget as
    # Gem::YAMLSerializer::Builder, which keeps its own constant because Bundler
    # ships a copy of that file.
    private_class_method def self.check_alias_expansion(input)
      sizes = {}
      expansion = 0
      count = lambda do |node|
        if node.is_a?(::Psych::Nodes::Alias)
          size = sizes.fetch(node.anchor, 0)
          expansion += size
          if expansion > MAX_ALIAS_EXPANSION
            raise ::Psych::BadAlias, "exceeded maximum alias expansion (#{MAX_ALIAS_EXPANSION})"
          end
          next size
        end

        size = node.is_a?(::Psych::Nodes::Scalar) ? 1 + node.value.bytesize : 1 + node.children.sum(&count)
        sizes[node.anchor] = size if node.respond_to?(:anchor) && node.anchor
        size
      end
      document = ::Psych.parse(input)
      count.call(document) if document
    end
  end
end
