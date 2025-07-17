# frozen_string_literal: true

require "rubygems" unless defined?(Gem)

# We can't let `Gem::Source` be autoloaded in the `Gem::Specification#source`
# redefinition below, so we need to load it upfront. The reason is that if
# Bundler monkeypatches are loaded before RubyGems activates an executable (for
# example, through `ruby -rbundler -S irb`), gem activation might end up calling
# the redefined `Gem::Specification#source` and triggering the `Gem::Source`
# autoload. That would result in requiring "rubygems/source" inside another
# require, which would trigger a monitor error and cause the `autoload` to
# eventually fail. A better solution is probably to completely avoid autoloading
# `Gem::Source` from the redefined `Gem::Specification#source`.
require "rubygems/source"

module Gem
  # Can be removed once RubyGems 3.5.11 support is dropped
  unless Gem.respond_to?(:freebsd_platform?)
    def self.freebsd_platform?
      RbConfig::CONFIG["host_os"].to_s.include?("bsd")
    end
  end

  # Can be removed once RubyGems 3.5.18 support is dropped
  unless Gem.respond_to?(:open_file_with_lock)
    class << self
      remove_method :open_file_with_flock if Gem.respond_to?(:open_file_with_flock)

      def open_file_with_flock(path, &block)
        # read-write mode is used rather than read-only in order to support NFS
        mode = IO::RDWR | IO::APPEND | IO::CREAT | IO::BINARY
        mode |= IO::SHARE_DELETE if IO.const_defined?(:SHARE_DELETE)

        File.open(path, mode) do |io|
          begin
            io.flock(File::LOCK_EX)
          rescue Errno::ENOSYS, Errno::ENOTSUP
          end
          yield io
        end
      end

      def open_file_with_lock(path, &block)
        file_lock = "#{path}.lock"
        open_file_with_flock(file_lock, &block)
      ensure
        FileUtils.rm_f file_lock
      end
    end
  end

  require "rubygems/platform"

  class Platform
    # Can be removed once RubyGems 3.6.9 support is dropped
    unless respond_to?(:generic)
      JAVA  = Gem::Platform.new("java") # :nodoc:
      MSWIN = Gem::Platform.new("mswin32") # :nodoc:
      MSWIN64 = Gem::Platform.new("mswin64") # :nodoc:
      MINGW = Gem::Platform.new("x86-mingw32") # :nodoc:
      X64_MINGW_LEGACY = Gem::Platform.new("x64-mingw32") # :nodoc:
      X64_MINGW = Gem::Platform.new("x64-mingw-ucrt") # :nodoc:
      UNIVERSAL_MINGW = Gem::Platform.new("universal-mingw") # :nodoc:
      WINDOWS = [MSWIN, MSWIN64, UNIVERSAL_MINGW].freeze # :nodoc:
      X64_LINUX = Gem::Platform.new("x86_64-linux") # :nodoc:
      X64_LINUX_MUSL = Gem::Platform.new("x86_64-linux-musl") # :nodoc:

      GENERICS = [JAVA, *WINDOWS].freeze # :nodoc:
      private_constant :GENERICS

      GENERIC_CACHE = GENERICS.each_with_object({}) {|g, h| h[g] = g } # :nodoc:
      private_constant :GENERIC_CACHE

      class << self
        ##
        # Returns the generic platform for the given platform.

        def generic(platform)
          return Gem::Platform::RUBY if platform.nil? || platform == Gem::Platform::RUBY

          GENERIC_CACHE[platform] ||= begin
            found = GENERICS.find do |match|
              platform === match
            end
            found || Gem::Platform::RUBY
          end
        end

        ##
        # Returns the platform specificity match for the given spec platform and user platform.

        def platform_specificity_match(spec_platform, user_platform)
          return -1 if spec_platform == user_platform
          return 1_000_000 if spec_platform.nil? || spec_platform == Gem::Platform::RUBY || user_platform == Gem::Platform::RUBY

          os_match(spec_platform, user_platform) +
            cpu_match(spec_platform, user_platform) * 10 +
            version_match(spec_platform, user_platform) * 100
        end

        ##
        # Sorts and filters the best platform match for the given matching specs and platform.

        def sort_and_filter_best_platform_match(matching, platform)
          return matching if matching.one?

          exact = matching.select {|spec| spec.platform == platform }
          return exact if exact.any?

          sorted_matching = sort_best_platform_match(matching, platform)
          exemplary_spec = sorted_matching.first

          sorted_matching.take_while {|spec| same_specificity?(platform, spec, exemplary_spec) && same_deps?(spec, exemplary_spec) }
        end

        ##
        # Sorts the best platform match for the given matching specs and platform.

        def sort_best_platform_match(matching, platform)
          matching.sort_by.with_index do |spec, i|
            [
              platform_specificity_match(spec.platform, platform),
              i, # for stable sort
            ]
          end
        end

        private

        def same_specificity?(platform, spec, exemplary_spec)
          platform_specificity_match(spec.platform, platform) == platform_specificity_match(exemplary_spec.platform, platform)
        end

        def same_deps?(spec, exemplary_spec)
          spec.required_ruby_version == exemplary_spec.required_ruby_version &&
            spec.required_rubygems_version == exemplary_spec.required_rubygems_version &&
            spec.dependencies.sort == exemplary_spec.dependencies.sort
        end

        def os_match(spec_platform, user_platform)
          if spec_platform.os == user_platform.os
            0
          else
            1
          end
        end

        def cpu_match(spec_platform, user_platform)
          if spec_platform.cpu == user_platform.cpu
            0
          elsif spec_platform.cpu == "arm" && user_platform.cpu.to_s.start_with?("arm")
            0
          elsif spec_platform.cpu.nil? || spec_platform.cpu == "universal"
            1
          else
            2
          end
        end

        def version_match(spec_platform, user_platform)
          if spec_platform.version == user_platform.version
            0
          elsif spec_platform.version.nil?
            1
          else
            2
          end
        end
      end

    end
  end

  require "rubygems/specification"

  # Can be removed once RubyGems 3.5.14 support is dropped
  VALIDATES_FOR_RESOLUTION = Specification.new.respond_to?(:validate_for_resolution).freeze

  class Specification
    # Can be removed once RubyGems 3.5.15 support is dropped
    correct_array_attributes = @@default_value.select {|_k,v| v.is_a?(Array) }.keys
    unless @@array_attributes == correct_array_attributes
      @@array_attributes = correct_array_attributes # rubocop:disable Style/ClassVars
    end

    require_relative "match_metadata"
    require_relative "match_platform"

    include ::Bundler::MatchMetadata

    attr_accessor :remote, :relative_loaded_from

    module AllowSettingSource
      attr_writer :source

      def source
        (defined?(@source) && @source) || super
      end
    end

    prepend AllowSettingSource

    alias_method :rg_full_gem_path, :full_gem_path
    alias_method :rg_loaded_from,   :loaded_from

    def full_gem_path
      if source.respond_to?(:root)
        File.expand_path(File.dirname(loaded_from), source.root)
      else
        rg_full_gem_path
      end
    end

    def loaded_from
      if relative_loaded_from
        source.path.join(relative_loaded_from).to_s
      else
        rg_loaded_from
      end
    end

    def load_paths
      full_require_paths
    end

    alias_method :rg_extension_dir, :extension_dir
    def extension_dir
      # following instance variable is already used in original method
      # and that is the reason to prefix it with bundler_ and add rubocop exception
      @bundler_extension_dir ||= if source.respond_to?(:extension_dir_name) # rubocop:disable Naming/MemoizedInstanceVariableName
        unique_extension_dir = [source.extension_dir_name, File.basename(full_gem_path)].uniq.join("-")
        File.expand_path(File.join(extensions_dir, unique_extension_dir))
      else
        rg_extension_dir
      end
    end

    # Can be removed once RubyGems 3.5.21 support is dropped
    remove_method :gem_dir if method_defined?(:gem_dir, false)

    def gem_dir
      full_gem_path
    end

    def insecurely_materialized?
      false
    end

    def groups
      @groups ||= []
    end

    def git_version
      return unless loaded_from && source.is_a?(Bundler::Source::Git)
      " #{source.revision[0..6]}"
    end

    def to_gemfile(path = nil)
      gemfile = String.new("source 'https://rubygems.org'\n")
      gemfile << dependencies_to_gemfile(nondevelopment_dependencies)
      unless development_dependencies.empty?
        gemfile << "\n"
        gemfile << dependencies_to_gemfile(development_dependencies, :development)
      end
      gemfile
    end

    def nondevelopment_dependencies
      dependencies - development_dependencies
    end

    def installation_missing?
      !default_gem? && !File.directory?(full_gem_path)
    end

    def lock_name
      @lock_name ||= name_tuple.lock_name
    end

    unless VALIDATES_FOR_RESOLUTION
      def validate_for_resolution
        SpecificationPolicy.new(self).validate_for_resolution
      end
    end

    if Gem.rubygems_version < Gem::Version.new("3.5.22")
      module FixPathSourceMissingExtensions
        def missing_extensions?
          return false if %w[Bundler::Source::Path Bundler::Source::Gemspec].include?(source.class.name)

          super
        end
      end

      prepend FixPathSourceMissingExtensions
    end

    private

    def dependencies_to_gemfile(dependencies, group = nil)
      gemfile = String.new
      if dependencies.any?
        gemfile << "group :#{group} do\n" if group
        dependencies.each do |dependency|
          gemfile << "  " if group
          gemfile << %(gem "#{dependency.name}")
          req = dependency.requirements_list.first
          gemfile << %(, "#{req}") if req
          gemfile << "\n"
        end
        gemfile << "end\n" if group
      end
      gemfile
    end
  end

  unless VALIDATES_FOR_RESOLUTION
    class SpecificationPolicy
      def validate_for_resolution
        validate_required!
      end
    end
  end

  module BetterPermissionError
    def data
      super
    rescue Errno::EACCES
      raise Bundler::PermissionError.new(loaded_from, :read)
    end
  end

  require "rubygems/stub_specification"

  class StubSpecification
    prepend BetterPermissionError
  end

  class Dependency
    require_relative "force_platform"

    include ::Bundler::ForcePlatform

    attr_reader :force_ruby_platform

    attr_accessor :source, :groups

    alias_method :eql?, :==

    unless method_defined?(:encode_with, false)
      def encode_with(coder)
        [:@name, :@requirement, :@type, :@prerelease, :@version_requirements].each do |ivar|
          coder[ivar.to_s.sub(/^@/, "")] = instance_variable_get(ivar)
        end
      end
    end

    def to_lock
      out = String.new("  #{name}")
      unless requirement.none?
        reqs = requirement.requirements.map {|o, v| "#{o} #{v}" }.sort.reverse
        out << " (#{reqs.join(", ")})"
      end
      out
    end

    if Gem.rubygems_version < Gem::Version.new("3.5.22")
      module FilterIgnoredSpecs
        def matching_specs(platform_only = false)
          super.reject(&:ignored?)
        end
      end

      prepend FilterIgnoredSpecs
    end
  end

  # On universal Rubies, resolve the "universal" arch to the real CPU arch, without changing the extension directory.
  class BasicSpecification
    if /^universal\.(?<arch>.*?)-/ =~ (CROSS_COMPILING || RUBY_PLATFORM)
      local_platform = Platform.local
      if local_platform.cpu == "universal"
        ORIGINAL_LOCAL_PLATFORM = local_platform.to_s.freeze

        local_platform.cpu = if arch == "arm64e" # arm64e is only permitted for Apple system binaries
          "arm64"
        else
          arch
        end

        def extensions_dir
          @extensions_dir ||=
            Gem.default_ext_dir_for(base_dir) || File.join(base_dir, "extensions", ORIGINAL_LOCAL_PLATFORM, Gem.extension_api_version)
        end
      end
    end

    # Can be removed once RubyGems 3.5.22 support is dropped
    unless new.respond_to?(:ignored?)
      def ignored?
        return @ignored unless @ignored.nil?

        @ignored = missing_extensions?
      end
    end

    # Can be removed once RubyGems 3.6.9 support is dropped
    unless new.respond_to?(:installable_on_platform?)
      include(::Bundler::MatchPlatform)
    end
  end

  require "rubygems/name_tuple"

  class NameTuple
    # Versions of RubyGems before about 3.5.0 don't to_s the platform.
    unless Gem::NameTuple.new("a", Gem::Version.new("1"), Gem::Platform.new("x86_64-linux")).platform.is_a?(String)
      alias_method :initialize_with_platform, :initialize

      def initialize(name, version, platform=Gem::Platform::RUBY)
        if Gem::Platform === platform
          initialize_with_platform(name, version, platform.to_s)
        else
          initialize_with_platform(name, version, platform)
        end
      end
    end

    def lock_name
      if platform == Gem::Platform::RUBY
        "#{name} (#{version})"
      else
        "#{name} (#{version}-#{platform})"
      end
    end
  end

  unless Gem.rubygems_version >= Gem::Version.new("3.5.19")
    class Resolver::ActivationRequest
      remove_method :installed?

      def installed?
        case @spec
        when Gem::Resolver::VendorSpecification then
          true
        else
          this_spec = full_spec

          Gem::Specification.any? do |s|
            s == this_spec && s.base_dir == this_spec.base_dir
          end
        end
      end
    end
  end

  unless Gem.rubygems_version >= Gem::Version.new("3.6.7")
    module UnfreezeCompactIndexParsedResponse
      def parse(line)
        version, platform, dependencies, requirements = super
        [version, platform, dependencies.frozen? ? dependencies.dup : dependencies, requirements.frozen? ? requirements.dup : requirements]
      end
    end

    Resolver::APISet::GemParser.prepend(UnfreezeCompactIndexParsedResponse)
  end

  if Gem.rubygems_version < Gem::Version.new("3.6.0")
    class Package; end
    require "rubygems/package/tar_reader"
    require "rubygems/package/tar_reader/entry"

    module FixFullNameEncoding
      def full_name
        super.force_encoding(Encoding::UTF_8)
      end
    end

    Package::TarReader::Entry.prepend(FixFullNameEncoding)
  end
end
