# frozen_string_literal: true

require "uri"
require "bundler/match_platform"

module Bundler
  class LazySpecification
    Identifier = Struct.new(:name, :version, :source, :platform, :dependencies)
    class Identifier
      include Comparable
      def <=>(other)
        return unless other.is_a?(Identifier)
        [name, version, platform_string] <=> [other.name, other.version, other.platform_string]
      end

    protected

      def platform_string
        platform_string = platform.to_s
        platform_string == Index::RUBY ? Index::NULL : platform_string
      end
    end

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
      search_object = Bundler.feature_flag.specific_platform? || Bundler.settings[:force_ruby_platform] ? self : Dependency.new(name, version)
      @specification = if source.is_a?(Source::Gemspec) && source.gemspec.name == name
        source.gemspec.tap {|s| s.source = source }
      else
        search = source.specs.search(search_object).last
        if search && Gem::Platform.new(search.platform) != Gem::Platform.new(platform) && !search.runtime_dependencies.-(dependencies.reject {|d| d.type == :development }).empty?
          Bundler.ui.warn "Unable to use the platform-specific (#{search.platform}) version of #{name} (#{version}) " \
            "because it has different dependencies from the #{platform} version. " \
            "To use the platform-specific version of the gem, run `bundle config specific_platform true` and install again."
          search = source.specs.search(self).last
        end
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
      @__identifier ||= Identifier.new(name, version, source, platform, dependencies)
    end

    def git_version
      return unless source.is_a?(Bundler::Source::Git)
      " #{source.revision[0..6]}"
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
  end
end
