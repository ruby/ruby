# frozen_string_literal: true

module Bundler
  # Represents a lazily loaded gem specification, where the full specification
  # is on the source server in rubygems' "quick" index. The proxy object is to
  # be seeded with what we're given from the source's abbreviated index - the
  # full specification will only be fetched when necessary.
  class RemoteSpecification
    include MatchRemoteMetadata
    include MatchPlatform
    include Comparable

    attr_reader :name, :version, :platform
    attr_writer :dependencies
    attr_accessor :source, :remote

    def initialize(name, version, platform, spec_fetcher)
      @name         = name
      @version      = Gem::Version.create version
      @original_platform = platform || Gem::Platform::RUBY
      @platform     = Gem::Platform.new(platform)
      @spec_fetcher = spec_fetcher
      @dependencies = nil
    end

    # Needed before installs, since the arch matters then and quick
    # specs don't bother to include the arch in the platform string
    def fetch_platform
      @platform = _remote_specification.platform
    end

    def full_name
      @full_name ||= if @platform == Gem::Platform::RUBY
        "#{@name}-#{@version}"
      else
        "#{@name}-#{@version}-#{@platform}"
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
      raise APIResponseInvalidDependenciesError unless spec.dependencies.all? {|d| d.is_a?(Gem::Dependency) }

      SharedHelpers.ensure_same_dependencies(self, dependencies, spec.dependencies)
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

    def dependencies
      @dependencies ||= begin
        deps = method_missing(:dependencies)

        # allow us to handle when the specs dependencies are an array of array of string
        # in order to delay the crash to `#__swap__` where it results in a friendlier error
        # see https://github.com/rubygems/bundler/issues/5797
        deps = deps.map {|d| d.is_a?(Gem::Dependency) ? d : Gem::Dependency.new(*d) }

        deps
      end
    end

    def git_version
      return unless loaded_from && source.is_a?(Bundler::Source::Git)
      " #{source.revision[0..6]}"
    end

    # we don't get the checksum from a server like we could with EndpointSpecs
    # calculating the checksum from the file on disk still provides some measure of security
    # if it changes from install to install, that is cause for concern
    def to_checksum
      @checksum ||= begin
        gem_path = fetch_gem
        require "rubygems/package"
        package = Gem::Package.new(gem_path)
        digest = Bundler::Checksum.digest_from_file_source(package.gem)
        digest.hexdigest!
      end

      digest = "sha256-#{@checksum}" if @checksum
      Bundler::Checksum.new(name, version, platform, [digest])
    end

    private

    def to_ary
      nil
    end

    def fetch_gem
      fetch_platform

      cache_path = download_cache_path || default_cache_path_for_rubygems_dir
      gem_path = "#{cache_path}/#{file_name}"
      return gem_path if File.exist?(gem_path)

      SharedHelpers.filesystem_access(cache_path) do |p|
        FileUtils.mkdir_p(p)
      end

      Bundler.rubygems.download_gem(self, remote.uri, cache_path)

      gem_path
    end

    def download_cache_path
      return unless Bundler.feature_flag.global_gem_cache?
      return unless remote
      return unless remote.cache_slug

      Bundler.user_cache.join("gems", remote.cache_slug)
    end

    def default_cache_path_for_rubygems_dir
      "#{Bundler.bundle_path}/cache"
    end

    def _remote_specification
      @_remote_specification ||= @spec_fetcher.fetch_spec([@name, @version, @original_platform])
      @_remote_specification || raise(GemspecError, "Gemspec data for #{full_name} was" \
        " missing from the server!")
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
