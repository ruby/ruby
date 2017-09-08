# frozen_string_literal: true
require "uri"
require "rubygems/spec_fetcher"

module Bundler
  # Represents a lazily loaded gem specification, where the full specification
  # is on the source server in rubygems' "quick" index. The proxy object is to
  # be seeded with what we're given from the source's abbreviated index - the
  # full specification will only be fetched when necessary.
  class RemoteSpecification
    include MatchPlatform
    include Comparable

    attr_reader :name, :version, :platform
    attr_accessor :source, :remote

    def initialize(name, version, platform, spec_fetcher)
      @name         = name
      @version      = Gem::Version.create version
      @platform     = platform
      @spec_fetcher = spec_fetcher
    end

    # Needed before installs, since the arch matters then and quick
    # specs don't bother to include the arch in the platform string
    def fetch_platform
      @platform = _remote_specification.platform
    end

    def full_name
      if platform == Gem::Platform::RUBY || platform.nil?
        "#{@name}-#{@version}"
      else
        "#{@name}-#{@version}-#{platform}"
      end
    end

    # Compare this specification against another object. Using sort_obj
    # is compatible with Gem::Specification and other Bundler or RubyGems
    # objects. Otherwise, use the default Object comparison.
    def <=>(other)
      if other.respond_to?(:sort_obj)
        sort_obj <=> other.sort_obj
      else
        super
      end
    end

    # Because Rubyforge cannot be trusted to provide valid specifications
    # once the remote gem is downloaded, the backend specification will
    # be swapped out.
    def __swap__(spec)
      @_remote_specification = spec
    end

    # Create a delegate used for sorting. This strategy is copied from
    # RubyGems 2.23 and ensures that Bundler's specifications can be
    # compared and sorted with RubyGems' own specifications.
    #
    # @see #<=>
    # @see Gem::Specification#sort_obj
    #
    # @return [Array] an object you can use to compare and sort this
    #   specification against other specifications
    def sort_obj
      [@name, @version, @platform == Gem::Platform::RUBY ? -1 : 1]
    end

    def to_s
      "#<#{self.class} name=#{name} version=#{version} platform=#{platform}>"
    end

  private

    def _remote_specification
      @_remote_specification ||= @spec_fetcher.fetch_spec([@name, @version, @platform])
      @_remote_specification || raise(GemspecError, "Gemspec data for #{full_name} was" \
        " missing from the server! Try installing with `--full-index` as a workaround.")
    end

    def method_missing(method, *args, &blk)
      _remote_specification.send(method, *args, &blk)
    end

    def respond_to?(method, include_all = false)
      super || _remote_specification.respond_to?(method, include_all)
    end
    public :respond_to?
  end
end
