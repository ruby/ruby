# frozen_string_literal: true

require_relative "match_platform"

module Bundler
  class LazySpecification
    include MatchPlatform

    attr_reader :name, :version, :dependencies, :platform
    attr_accessor :source, :remote

    def initialize(name, version, platform, source = nil)
      @name          = name
      @version       = version
      @dependencies  = []
      @platform      = platform || Gem::Platform::RUBY
      @source        = source
      @specification = nil
    end

    def full_name
      if platform == Gem::Platform::RUBY || platform.nil?
        "#{@name}-#{@version}"
      else
        "#{@name}-#{@version}-#{platform}"
      end
    end

    def ==(other)
      identifier == other.identifier
    end

    def eql?(other)
      identifier.eql?(other.identifier)
    end

    def hash
      identifier.hash
    end

    def satisfies?(dependency)
      @name == dependency.name && dependency.requirement.satisfied_by?(Gem::Version.new(@version))
    end

    def to_lock
      out = String.new

      if platform == Gem::Platform::RUBY || platform.nil?
        out << "    #{name} (#{version})\n"
      else
        out << "    #{name} (#{version}-#{platform})\n"
      end

      dependencies.sort_by(&:to_s).uniq.each do |dep|
        next if dep.type == :development
        out << "    #{dep.to_lock}\n"
      end

      out
    end

    def __materialize__
      @specification = if source.is_a?(Source::Gemspec) && source.gemspec.name == name
        source.gemspec.tap {|s| s.source = source }
      else
        search_object = if source.is_a?(Source::Path)
          Dependency.new(name, version)
        else
          ruby_platform_materializes_to_ruby_platform? ? self : Dependency.new(name, version)
        end
        platform_object = Gem::Platform.new(platform)
        candidates = source.specs.search(search_object)
        same_platform_candidates = candidates.select do |spec|
          MatchPlatform.platforms_match?(spec.platform, platform_object)
        end
        installable_candidates = same_platform_candidates.select do |spec|
          !spec.is_a?(EndpointSpecification) ||
            (spec.required_ruby_version.satisfied_by?(Gem.ruby_version) &&
              spec.required_rubygems_version.satisfied_by?(Gem.rubygems_version))
        end
        search = installable_candidates.last || same_platform_candidates.last
        search.dependencies = dependencies if search && (search.is_a?(RemoteSpecification) || search.is_a?(EndpointSpecification))
        search
      end
    end

    def respond_to?(*args)
      super || @specification ? @specification.respond_to?(*args) : nil
    end

    def to_s
      @__to_s ||= if platform == Gem::Platform::RUBY || platform.nil?
        "#{name} (#{version})"
      else
        "#{name} (#{version}-#{platform})"
      end
    end

    def identifier
      @__identifier ||= [name, version, platform_string]
    end

    def git_version
      return unless source.is_a?(Bundler::Source::Git)
      " #{source.revision[0..6]}"
    end

    protected

    def platform_string
      platform_string = platform.to_s
      platform_string == Index::RUBY ? Index::NULL : platform_string
    end

    private

    def to_ary
      nil
    end

    def method_missing(method, *args, &blk)
      raise "LazySpecification has not been materialized yet (calling :#{method} #{args.inspect})" unless @specification

      return super unless respond_to?(method)

      @specification.send(method, *args, &blk)
    end

    #
    # For backwards compatibility with existing lockfiles, if the most specific
    # locked platform is RUBY, we keep the previous behaviour of resolving the
    # best platform variant at materiliazation time. For previous bundler
    # versions (before 2.2.0) this was always the case (except when the lockfile
    # only included non-ruby platforms), but we're also keeping this behaviour
    # on newer bundlers unless users generate the lockfile from scratch or
    # explicitly add a more specific platform.
    #
    def ruby_platform_materializes_to_ruby_platform?
      !Bundler.most_specific_locked_platform?(Gem::Platform::RUBY) || Bundler.settings[:force_ruby_platform]
    end
  end
end
