# frozen_string_literal: true

module Bundler
  class RubyVersion
    attr_reader :versions,
      :patchlevel,
      :engine,
      :engine_versions,
      :gem_version,
      :engine_gem_version

    def initialize(versions, patchlevel, engine, engine_version)
      # The parameters to this method must satisfy the
      # following constraints, which are verified in
      # the DSL:
      #
      # * If an engine is specified, an engine version
      #   must also be specified
      # * If an engine version is specified, an engine
      #   must also be specified
      # * If the engine is "ruby", the engine version
      #   must not be specified, or the engine version
      #   specified must match the version.

      @versions = Array(versions).map do |v|
        op, v = Gem::Requirement.parse(v)
        op == "=" ? v.to_s : "#{op} #{v}"
      end

      @gem_version        = Gem::Requirement.create(@versions.first).requirements.first.last
      @input_engine       = engine && engine.to_s
      @engine             = engine && engine.to_s || "ruby"
      @engine_versions    = (engine_version && Array(engine_version)) || @versions
      @engine_gem_version = Gem::Requirement.create(@engine_versions.first).requirements.first.last
      @patchlevel         = patchlevel
    end

    def to_s(versions = self.versions)
      output = String.new("ruby #{versions_string(versions)}")
      output << "p#{patchlevel}" if patchlevel
      output << " (#{engine} #{versions_string(engine_versions)})" unless engine == "ruby"

      output
    end

    # @private
    PATTERN = /
      ruby\s
      ([\d.]+) # ruby version
      (?:p(-?\d+))? # optional patchlevel
      (?:\s\((\S+)\s(.+)\))? # optional engine info
    /xo.freeze

    # Returns a RubyVersion from the given string.
    # @param [String] the version string to match.
    # @return [RubyVersion,Nil] The version if the string is a valid RubyVersion
    #         description, and nil otherwise.
    def self.from_string(string)
      new($1, $2, $3, $4) if string =~ PATTERN
    end

    def single_version_string
      to_s(gem_version)
    end

    def ==(other)
      versions == other.versions &&
        engine == other.engine &&
        engine_versions == other.engine_versions &&
        patchlevel == other.patchlevel
    end

    def host
      @host ||= [
        RbConfig::CONFIG["host_cpu"],
        RbConfig::CONFIG["host_vendor"],
        RbConfig::CONFIG["host_os"],
      ].join("-")
    end

    # Returns a tuple of these things:
    #   [diff, this, other]
    #   The priority of attributes are
    #   1. engine
    #   2. ruby_version
    #   3. engine_version
    def diff(other)
      raise ArgumentError, "Can only diff with a RubyVersion, not a #{other.class}" unless other.is_a?(RubyVersion)
      if engine != other.engine && @input_engine
        [:engine, engine, other.engine]
      elsif versions.empty? || !matches?(versions, other.gem_version)
        [:version, versions_string(versions), versions_string(other.versions)]
      elsif @input_engine && !matches?(engine_versions, other.engine_gem_version)
        [:engine_version, versions_string(engine_versions), versions_string(other.engine_versions)]
      elsif patchlevel && (!patchlevel.is_a?(String) || !other.patchlevel.is_a?(String) || !matches?(patchlevel, other.patchlevel))
        [:patchlevel, patchlevel, other.patchlevel]
      end
    end

    def versions_string(versions)
      Array(versions).join(", ")
    end

    def self.system
      ruby_engine = if defined?(RUBY_ENGINE) && !RUBY_ENGINE.nil?
        RUBY_ENGINE.dup
      else
        # not defined in ruby 1.8.7
        "ruby"
      end
      # :sob: mocking RUBY_VERSION breaks stuff on 1.8.7
      ruby_version = ENV.fetch("BUNDLER_SPEC_RUBY_VERSION") { RUBY_VERSION }.dup
      ruby_engine_version = case ruby_engine
                            when "ruby"
                              ruby_version
                            when "rbx"
                              Rubinius::VERSION.dup
                            when "jruby"
                              JRUBY_VERSION.dup
                            else
                              RUBY_ENGINE_VERSION.dup
      end
      patchlevel = RUBY_PATCHLEVEL.to_s

      @ruby_version ||= RubyVersion.new(ruby_version, patchlevel, ruby_engine, ruby_engine_version)
    end

    def to_gem_version_with_patchlevel
      @gem_version_with_patch ||= begin
        Gem::Version.create("#{@gem_version}.#{@patchlevel}")
      rescue ArgumentError
        @gem_version
      end
    end

    def exact?
      return @exact if defined?(@exact)
      @exact = versions.all? {|v| Gem::Requirement.create(v).exact? }
    end

  private

    def matches?(requirements, version)
      # Handles RUBY_PATCHLEVEL of -1 for instances like ruby-head
      return requirements == version if requirements.to_s == "-1" || version.to_s == "-1"

      Array(requirements).all? do |requirement|
        Gem::Requirement.create(requirement).satisfied_by?(Gem::Version.create(version))
      end
    end
  end
end
