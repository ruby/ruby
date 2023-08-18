# frozen_string_literal: true

require_relative "safe_marshal/reader"
require_relative "safe_marshal/visitors/to_ruby"

module Gem
  ###
  # This module is used for safely loading Marshal specs from a gem.  The
  # `safe_load` method defined on this module is specifically designed for
  # loading Gem specifications.

  module SafeMarshal
    PERMITTED_CLASSES = %w[
      Time
      Date

      Gem::Dependency
      Gem::NameTuple
      Gem::Platform
      Gem::Requirement
      Gem::Specification
      Gem::Version
      Gem::Version::Requirement

      YAML::Syck::DefaultKey
      YAML::PrivateType
    ].freeze
    private_constant :PERMITTED_CLASSES

    PERMITTED_SYMBOLS = %w[
      E

      offset
      zone
      nano_num
      nano_den
      submicro

      @_zone
      @cpu
      @force_ruby_platform
      @marshal_with_utc_coercion
      @name
      @os
      @platform
      @prerelease
      @requirement
      @taguri
      @type
      @type_id
      @value
      @version
      @version_requirement
      @version_requirements

      development
      runtime
    ].freeze
    private_constant :PERMITTED_SYMBOLS

    def self.safe_load(input)
      load(input, permitted_classes: PERMITTED_CLASSES, permitted_symbols: PERMITTED_SYMBOLS)
    end

    def self.load(input, permitted_classes: [::Symbol], permitted_symbols: [])
      root = Reader.new(StringIO.new(input, "r")).read!

      Visitors::ToRuby.new(permitted_classes: permitted_classes, permitted_symbols: permitted_symbols).visit(root)
    end
  end
end
