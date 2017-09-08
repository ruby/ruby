# frozen_string_literal: true

# Some versions of the Bundler 1.1 RC series introduced corrupted
# lockfiles. There were two major problems:
#
# * multiple copies of the same GIT section appeared in the lockfile
# * when this happened, those sections got multiple copies of gems
#   in those sections.
#
# As a result, Bundler 1.1 contains code that fixes the earlier
# corruption. We will remove this fix-up code in Bundler 1.2.

module Bundler
  class LockfileParser
    attr_reader :sources, :dependencies, :specs, :platforms, :bundler_version, :ruby_version

    BUNDLED      = "BUNDLED WITH".freeze
    DEPENDENCIES = "DEPENDENCIES".freeze
    PLATFORMS    = "PLATFORMS".freeze
    RUBY         = "RUBY VERSION".freeze
    GIT          = "GIT".freeze
    GEM          = "GEM".freeze
    PATH         = "PATH".freeze
    PLUGIN       = "PLUGIN SOURCE".freeze
    SPECS        = "  specs:".freeze
    OPTIONS      = /^  ([a-z]+): (.*)$/i
    SOURCE       = [GIT, GEM, PATH, PLUGIN].freeze

    SECTIONS_BY_VERSION_INTRODUCED = {
      # The strings have to be dup'ed for old RG on Ruby 2.3+
      # TODO: remove dup in Bundler 2.0
      Gem::Version.create("1.0".dup) => [DEPENDENCIES, PLATFORMS, GIT, GEM, PATH].freeze,
      Gem::Version.create("1.10".dup) => [BUNDLED].freeze,
      Gem::Version.create("1.12".dup) => [RUBY].freeze,
      Gem::Version.create("1.13".dup) => [PLUGIN].freeze,
    }.freeze

    KNOWN_SECTIONS = SECTIONS_BY_VERSION_INTRODUCED.values.flatten.freeze

    ENVIRONMENT_VERSION_SECTIONS = [BUNDLED, RUBY].freeze

    def self.sections_in_lockfile(lockfile_contents)
      lockfile_contents.scan(/^\w[\w ]*$/).uniq
    end

    def self.unknown_sections_in_lockfile(lockfile_contents)
      sections_in_lockfile(lockfile_contents) - KNOWN_SECTIONS
    end

    def self.sections_to_ignore(base_version = nil)
      base_version &&= base_version.release
      base_version ||= Gem::Version.create("1.0".dup)
      attributes = []
      SECTIONS_BY_VERSION_INTRODUCED.each do |version, introduced|
        next if version <= base_version
        attributes += introduced
      end
      attributes
    end

    def initialize(lockfile)
      @platforms    = []
      @sources      = []
      @dependencies = {}
      @state        = nil
      @specs        = {}

      @rubygems_aggregate = Source::Rubygems.new

      if lockfile.match(/<<<<<<<|=======|>>>>>>>|\|\|\|\|\|\|\|/)
        raise LockfileError, "Your #{Bundler.default_lockfile.relative_path_from(SharedHelpers.pwd)} contains merge conflicts.\n" \
          "Run `git checkout HEAD -- #{Bundler.default_lockfile.relative_path_from(SharedHelpers.pwd)}` first to get a clean lock."
      end

      lockfile.split(/(?:\r?\n)+/).each do |line|
        if SOURCE.include?(line)
          @state = :source
          parse_source(line)
        elsif line == DEPENDENCIES
          @state = :dependency
        elsif line == PLATFORMS
          @state = :platform
        elsif line == RUBY
          @state = :ruby
        elsif line == BUNDLED
          @state = :bundled_with
        elsif line =~ /^[^\s]/
          @state = nil
        elsif @state
          send("parse_#{@state}", line)
        end
      end
      @sources << @rubygems_aggregate
      @specs = @specs.values.sort_by(&:identifier)
      warn_for_outdated_bundler_version
    rescue ArgumentError => e
      Bundler.ui.debug(e)
      raise LockfileError, "Your lockfile is unreadable. Run `rm #{Bundler.default_lockfile.relative_path_from(SharedHelpers.pwd)}` " \
        "and then `bundle install` to generate a new lockfile."
    end

    def warn_for_outdated_bundler_version
      return unless bundler_version
      prerelease_text = bundler_version.prerelease? ? " --pre" : ""
      current_version = Gem::Version.create(Bundler::VERSION)
      case current_version.segments.first <=> bundler_version.segments.first
      when -1
        raise LockfileError, "You must use Bundler #{bundler_version.segments.first} or greater with this lockfile."
      when 0
        if current_version < bundler_version
          Bundler.ui.warn "Warning: the running version of Bundler (#{current_version}) is older " \
               "than the version that created the lockfile (#{bundler_version}). We suggest you " \
               "upgrade to the latest version of Bundler by running `gem " \
               "install bundler#{prerelease_text}`.\n"
        end
      end
    end

  private

    TYPES = {
      GIT    => Bundler::Source::Git,
      GEM    => Bundler::Source::Rubygems,
      PATH   => Bundler::Source::Path,
      PLUGIN => Bundler::Plugin,
    }.freeze

    def parse_source(line)
      case line
      when SPECS
        case @type
        when PATH
          @current_source = TYPES[@type].from_lock(@opts)
          @sources << @current_source
        when GIT
          @current_source = TYPES[@type].from_lock(@opts)
          # Strip out duplicate GIT sections
          if @sources.include?(@current_source)
            @current_source = @sources.find {|s| s == @current_source }
          else
            @sources << @current_source
          end
        when GEM
          Array(@opts["remote"]).each do |url|
            @rubygems_aggregate.add_remote(url)
          end
          @current_source = @rubygems_aggregate
        when PLUGIN
          @current_source = Plugin.source_from_lock(@opts)
          @sources << @current_source
        end
      when OPTIONS
        value = $2
        value = true if value == "true"
        value = false if value == "false"

        key = $1

        if @opts[key]
          @opts[key] = Array(@opts[key])
          @opts[key] << value
        else
          @opts[key] = value
        end
      when *SOURCE
        @current_source = nil
        @opts = {}
        @type = line
      else
        parse_spec(line)
      end
    end

    space = / /
    NAME_VERSION = /
      ^(#{space}{2}|#{space}{4}|#{space}{6})(?!#{space}) # Exactly 2, 4, or 6 spaces at the start of the line
      (.*?)                                              # Name
      (?:#{space}\(([^-]*)                               # Space, followed by version
      (?:-(.*))?\))?                                     # Optional platform
      (!)?                                               # Optional pinned marker
      $                                                  # Line end
    /xo

    def parse_dependency(line)
      return unless line =~ NAME_VERSION
      spaces = $1
      return unless spaces.size == 2
      name = $2
      version = $3
      pinned = $5

      version = version.split(",").map(&:strip) if version

      dep = Bundler::Dependency.new(name, version)

      if pinned && dep.name != "bundler"
        spec = @specs.find {|_, v| v.name == dep.name }
        dep.source = spec.last.source if spec

        # Path sources need to know what the default name / version
        # to use in the case that there are no gemspecs present. A fake
        # gemspec is created based on the version set on the dependency
        # TODO: Use the version from the spec instead of from the dependency
        if version && version.size == 1 && version.first =~ /^\s*= (.+)\s*$/ && dep.source.is_a?(Bundler::Source::Path)
          dep.source.name    = name
          dep.source.version = $1
        end
      end

      @dependencies[dep.name] = dep
    end

    def parse_spec(line)
      return unless line =~ NAME_VERSION
      spaces = $1
      name = $2
      version = $3
      platform = $4

      if spaces.size == 4
        version = Gem::Version.new(version)
        platform = platform ? Gem::Platform.new(platform) : Gem::Platform::RUBY
        @current_spec = LazySpecification.new(name, version, platform)
        @current_spec.source = @current_source

        # Avoid introducing multiple copies of the same spec (caused by
        # duplicate GIT sections)
        @specs[@current_spec.identifier] ||= @current_spec
      elsif spaces.size == 6
        version = version.split(",").map(&:strip) if version
        dep = Gem::Dependency.new(name, version)
        @current_spec.dependencies << dep
      end
    end

    def parse_platform(line)
      @platforms << Gem::Platform.new($1) if line =~ /^  (.*)$/
    end

    def parse_bundled_with(line)
      line = line.strip
      return unless Gem::Version.correct?(line)
      @bundler_version = Gem::Version.create(line)
    end

    def parse_ruby(line)
      @ruby_version = line.strip
    end
  end
end
