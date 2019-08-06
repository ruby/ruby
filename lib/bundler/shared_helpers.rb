# frozen_string_literal: true

require "pathname"
require "rbconfig"

require_relative "version"
require_relative "constants"
require_relative "rubygems_integration"
require_relative "current_ruby"

module Bundler
  module SharedHelpers
    def root
      gemfile = find_gemfile
      raise GemfileNotFound, "Could not locate Gemfile" unless gemfile
      Pathname.new(gemfile).untaint.expand_path.parent
    end

    def default_gemfile
      gemfile = find_gemfile
      raise GemfileNotFound, "Could not locate Gemfile" unless gemfile
      Pathname.new(gemfile).untaint.expand_path
    end

    def default_lockfile
      gemfile = default_gemfile

      case gemfile.basename.to_s
      when "gems.rb" then Pathname.new(gemfile.sub(/.rb$/, ".locked"))
      else Pathname.new("#{gemfile}.lock")
      end.untaint
    end

    def default_bundle_dir
      bundle_dir = find_directory(".bundle")
      return nil unless bundle_dir

      bundle_dir = Pathname.new(bundle_dir)

      global_bundle_dir = Bundler.user_home.join(".bundle")
      return nil if bundle_dir == global_bundle_dir

      bundle_dir
    end

    def in_bundle?
      find_gemfile
    end

    def chdir(dir, &blk)
      Bundler.rubygems.ext_lock.synchronize do
        Dir.chdir dir, &blk
      end
    end

    def pwd
      Bundler.rubygems.ext_lock.synchronize do
        Pathname.pwd
      end
    end

    def with_clean_git_env(&block)
      keys    = %w[GIT_DIR GIT_WORK_TREE]
      old_env = keys.inject({}) do |h, k|
        h.update(k => ENV[k])
      end

      keys.each {|key| ENV.delete(key) }

      block.call
    ensure
      keys.each {|key| ENV[key] = old_env[key] }
    end

    def set_bundle_environment
      set_bundle_variables
      set_path
      set_rubyopt
      set_rubylib
    end

    # Rescues permissions errors raised by file system operations
    # (ie. Errno:EACCESS, Errno::EAGAIN) and raises more friendly errors instead.
    #
    # @param path [String] the path that the action will be attempted to
    # @param action [Symbol, #to_s] the type of operation that will be
    #   performed. For example: :write, :read, :exec
    #
    # @yield path
    #
    # @raise [Bundler::PermissionError] if Errno:EACCES is raised in the
    #   given block
    # @raise [Bundler::TemporaryResourceError] if Errno:EAGAIN is raised in the
    #   given block
    #
    # @example
    #   filesystem_access("vendor/cache", :write) do
    #     FileUtils.mkdir_p("vendor/cache")
    #   end
    #
    # @see {Bundler::PermissionError}
    def filesystem_access(path, action = :write, &block)
      yield(path.dup.untaint)
    rescue Errno::EACCES
      raise PermissionError.new(path, action)
    rescue Errno::EAGAIN
      raise TemporaryResourceError.new(path, action)
    rescue Errno::EPROTO
      raise VirtualProtocolError.new
    rescue Errno::ENOSPC
      raise NoSpaceOnDeviceError.new(path, action)
    rescue *[const_get_safely(:ENOTSUP, Errno)].compact
      raise OperationNotSupportedError.new(path, action)
    rescue Errno::EEXIST, Errno::ENOENT
      raise
    rescue SystemCallError => e
      raise GenericSystemCallError.new(e, "There was an error accessing `#{path}`.")
    end

    def const_get_safely(constant_name, namespace)
      const_in_namespace = namespace.constants.include?(constant_name.to_s) ||
        namespace.constants.include?(constant_name.to_sym)
      return nil unless const_in_namespace
      namespace.const_get(constant_name)
    end

    def major_deprecation(major_version, message)
      bundler_major_version = Bundler.bundler_major_version
      if bundler_major_version > major_version
        require_relative "errors"
        raise DeprecatedError, "[REMOVED] #{message}"
      end

      return unless bundler_major_version >= major_version && prints_major_deprecations?
      @major_deprecation_ui ||= Bundler::UI::Shell.new("no-color" => true)
      with_major_deprecation_ui do |ui|
        ui.warn("[DEPRECATED] #{message}")
      end
    end

    def print_major_deprecations!
      multiple_gemfiles = search_up(".") do |dir|
        gemfiles = gemfile_names.select {|gf| File.file? File.expand_path(gf, dir) }
        next if gemfiles.empty?
        break gemfiles.size != 1
      end
      return unless multiple_gemfiles
      message = "Multiple gemfiles (gems.rb and Gemfile) detected. " \
                "Make sure you remove Gemfile and Gemfile.lock since bundler is ignoring them in favor of gems.rb and gems.rb.locked."
      Bundler.ui.warn message
    end

    def trap(signal, override = false, &block)
      prior = Signal.trap(signal) do
        block.call
        prior.call unless override
      end
    end

    def ensure_same_dependencies(spec, old_deps, new_deps)
      new_deps = new_deps.reject {|d| d.type == :development }
      old_deps = old_deps.reject {|d| d.type == :development }

      without_type = proc {|d| Gem::Dependency.new(d.name, d.requirements_list.sort) }
      new_deps.map!(&without_type)
      old_deps.map!(&without_type)

      extra_deps = new_deps - old_deps
      return if extra_deps.empty?

      Bundler.ui.debug "#{spec.full_name} from #{spec.remote} has either corrupted API or lockfile dependencies" \
        " (was expecting #{old_deps.map(&:to_s)}, but the real spec has #{new_deps.map(&:to_s)})"
      raise APIResponseMismatchError,
        "Downloading #{spec.full_name} revealed dependencies not in the API or the lockfile (#{extra_deps.join(", ")})." \
        "\nEither installing with `--full-index` or running `bundle update #{spec.name}` should fix the problem."
    end

    def pretty_dependency(dep, print_source = false)
      msg = String.new(dep.name)
      msg << " (#{dep.requirement})" unless dep.requirement == Gem::Requirement.default

      if dep.is_a?(Bundler::Dependency)
        platform_string = dep.platforms.join(", ")
        msg << " " << platform_string if !platform_string.empty? && platform_string != Gem::Platform::RUBY
      end

      msg << " from the `#{dep.source}` source" if print_source && dep.source
      msg
    end

    def md5_available?
      return @md5_available if defined?(@md5_available)
      @md5_available = begin
        require "openssl"
        OpenSSL::Digest::MD5.digest("")
        true
      rescue LoadError
        true
      rescue OpenSSL::Digest::DigestError
        false
      end
    end

    def digest(name)
      require "digest"
      Digest(name)
    end

    def write_to_gemfile(gemfile_path, contents)
      filesystem_access(gemfile_path) {|g| File.open(g, "w") {|file| file.puts contents } }
    end

  private

    def with_major_deprecation_ui(&block)
      ui = Bundler.ui

      if ui.is_a?(@major_deprecation_ui.class)
        yield ui
      else
        begin
          Bundler.ui = @major_deprecation_ui
          yield Bundler.ui
        ensure
          Bundler.ui = ui
        end
      end
    end

    def validate_bundle_path
      path_separator = Bundler.rubygems.path_separator
      return unless Bundler.bundle_path.to_s.split(path_separator).size > 1
      message = "Your bundle path contains text matching #{path_separator.inspect}, " \
                "which is the path separator for your system. Bundler cannot " \
                "function correctly when the Bundle path contains the " \
                "system's PATH separator. Please change your " \
                "bundle path to not match #{path_separator.inspect}." \
                "\nYour current bundle path is '#{Bundler.bundle_path}'."
      raise Bundler::PathError, message
    end

    def find_gemfile
      given = ENV["BUNDLE_GEMFILE"]
      return given if given && !given.empty?
      find_file(*gemfile_names)
    end

    def gemfile_names
      ["gems.rb", "Gemfile"]
    end

    def find_file(*names)
      search_up(*names) do |filename|
        return filename if File.file?(filename)
      end
    end

    def find_directory(*names)
      search_up(*names) do |dirname|
        return dirname if File.directory?(dirname)
      end
    end

    def search_up(*names)
      previous = nil
      current  = File.expand_path(SharedHelpers.pwd).untaint

      until !File.directory?(current) || current == previous
        if ENV["BUNDLE_SPEC_RUN"]
          # avoid stepping above the tmp directory when testing
          gemspec = if ENV["BUNDLE_RUBY"] && ENV["BUNDLE_GEM"]
            # for Ruby Core
            "lib/bundler/bundler.gemspec"
          else
            "bundler.gemspec"
          end

          # avoid stepping above the tmp directory when testing
          return nil if File.file?(File.join(current, gemspec))
        end

        names.each do |name|
          filename = File.join(current, name)
          yield filename
        end
        previous = current
        current = File.expand_path("..", current)
      end
    end

    def set_env(key, value)
      raise ArgumentError, "new key #{key}" unless EnvironmentPreserver::BUNDLER_KEYS.include?(key)
      orig_key = "#{EnvironmentPreserver::BUNDLER_PREFIX}#{key}"
      orig = ENV[key]
      orig ||= EnvironmentPreserver::INTENTIONALLY_NIL
      ENV[orig_key] ||= orig

      ENV[key] = value
    end
    public :set_env

    def set_bundle_variables
      # bundler exe & lib folders have same root folder, typical gem installation
      exe_file = File.expand_path("../../../exe/bundle", __FILE__)

      # for Ruby core repository testing
      exe_file = File.expand_path("../../../bin/bundle", __FILE__) unless File.exist?(exe_file)

      # bundler is a default gem, exe path is separate
      exe_file = Bundler.rubygems.bin_path("bundler", "bundle", VERSION) unless File.exist?(exe_file)

      Bundler::SharedHelpers.set_env "BUNDLE_BIN_PATH", exe_file
      Bundler::SharedHelpers.set_env "BUNDLE_GEMFILE", find_gemfile.to_s
      Bundler::SharedHelpers.set_env "BUNDLER_VERSION", Bundler::VERSION
    end

    def set_path
      validate_bundle_path
      paths = (ENV["PATH"] || "").split(File::PATH_SEPARATOR)
      paths.unshift "#{Bundler.bundle_path}/bin"
      Bundler::SharedHelpers.set_env "PATH", paths.uniq.join(File::PATH_SEPARATOR)
    end

    def set_rubyopt
      rubyopt = [ENV["RUBYOPT"]].compact
      setup_require = "-r#{File.expand_path("setup", __dir__)}"
      return if !rubyopt.empty? && rubyopt.first =~ /#{setup_require}/
      rubyopt.unshift setup_require
      Bundler::SharedHelpers.set_env "RUBYOPT", rubyopt.join(" ")
    end

    def set_rubylib
      rubylib = (ENV["RUBYLIB"] || "").split(File::PATH_SEPARATOR)
      rubylib.unshift bundler_ruby_lib unless RbConfig::CONFIG["rubylibdir"] == bundler_ruby_lib
      Bundler::SharedHelpers.set_env "RUBYLIB", rubylib.uniq.join(File::PATH_SEPARATOR)
    end

    def bundler_ruby_lib
      resolve_path File.expand_path("../..", __FILE__)
    end

    def clean_load_path
      bundler_lib = bundler_ruby_lib

      loaded_gem_paths = Bundler.rubygems.loaded_gem_paths

      $LOAD_PATH.reject! do |p|
        next if resolve_path(p).start_with?(bundler_lib)
        loaded_gem_paths.delete(p)
      end
      $LOAD_PATH.uniq!
    end

    def resolve_path(path)
      expanded = File.expand_path(path)
      return expanded unless File.respond_to?(:realpath) && File.exist?(expanded)

      File.realpath(expanded)
    end

    def prints_major_deprecations?
      require_relative "../bundler"
      return false if Bundler.settings[:silence_deprecations]
      require_relative "deprecate"
      return false if Bundler::Deprecate.skip
      true
    end

    extend self
  end
end
