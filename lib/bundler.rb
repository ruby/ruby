# frozen_string_literal: true

require "bundler/compatibility_guard"

require "bundler/vendored_fileutils"
require "pathname"
require "rbconfig"
require "thread"

require "bundler/errors"
require "bundler/environment_preserver"
require "bundler/plugin"
require "bundler/rubygems_ext"
require "bundler/rubygems_integration"
require "bundler/version"
require "bundler/constants"
require "bundler/current_ruby"
require "bundler/build_metadata"

module Bundler
  environment_preserver = EnvironmentPreserver.new(ENV, EnvironmentPreserver::BUNDLER_KEYS)
  ORIGINAL_ENV = environment_preserver.restore
  ENV.replace(environment_preserver.backup)
  SUDO_MUTEX = Mutex.new

  autoload :Definition,             "bundler/definition"
  autoload :Dependency,             "bundler/dependency"
  autoload :DepProxy,               "bundler/dep_proxy"
  autoload :Deprecate,              "bundler/deprecate"
  autoload :Dsl,                    "bundler/dsl"
  autoload :EndpointSpecification,  "bundler/endpoint_specification"
  autoload :Env,                    "bundler/env"
  autoload :Fetcher,                "bundler/fetcher"
  autoload :FeatureFlag,            "bundler/feature_flag"
  autoload :GemHelper,              "bundler/gem_helper"
  autoload :GemHelpers,             "bundler/gem_helpers"
  autoload :GemRemoteFetcher,       "bundler/gem_remote_fetcher"
  autoload :GemVersionPromoter,     "bundler/gem_version_promoter"
  autoload :Graph,                  "bundler/graph"
  autoload :Index,                  "bundler/index"
  autoload :Injector,               "bundler/injector"
  autoload :Installer,              "bundler/installer"
  autoload :LazySpecification,      "bundler/lazy_specification"
  autoload :LockfileParser,         "bundler/lockfile_parser"
  autoload :MatchPlatform,          "bundler/match_platform"
  autoload :ProcessLock,            "bundler/process_lock"
  autoload :RemoteSpecification,    "bundler/remote_specification"
  autoload :Resolver,               "bundler/resolver"
  autoload :Retry,                  "bundler/retry"
  autoload :RubyDsl,                "bundler/ruby_dsl"
  autoload :RubyGemsGemInstaller,   "bundler/rubygems_gem_installer"
  autoload :RubyVersion,            "bundler/ruby_version"
  autoload :Runtime,                "bundler/runtime"
  autoload :Settings,               "bundler/settings"
  autoload :SharedHelpers,          "bundler/shared_helpers"
  autoload :Source,                 "bundler/source"
  autoload :SourceList,             "bundler/source_list"
  autoload :SpecSet,                "bundler/spec_set"
  autoload :StubSpecification,      "bundler/stub_specification"
  autoload :UI,                     "bundler/ui"
  autoload :URICredentialsFilter,   "bundler/uri_credentials_filter"
  autoload :VersionRanges,          "bundler/version_ranges"

  class << self
    def configure
      @configured ||= configure_gem_home_and_path
    end

    def ui
      (defined?(@ui) && @ui) || (self.ui = UI::Silent.new)
    end

    def ui=(ui)
      Bundler.rubygems.ui = ui ? UI::RGProxy.new(ui) : nil
      @ui = ui
    end

    # Returns absolute path of where gems are installed on the filesystem.
    def bundle_path
      @bundle_path ||= Pathname.new(configured_bundle_path.path).expand_path(root)
    end

    def configured_bundle_path
      @configured_bundle_path ||= settings.path.tap(&:validate!)
    end

    # Returns absolute location of where binstubs are installed to.
    def bin_path
      @bin_path ||= begin
        path = settings[:bin] || "bin"
        path = Pathname.new(path).expand_path(root).expand_path
        SharedHelpers.filesystem_access(path) {|p| FileUtils.mkdir_p(p) }
        path
      end
    end

    def setup(*groups)
      # Return if all groups are already loaded
      return @setup if defined?(@setup) && @setup

      definition.validate_runtime!

      SharedHelpers.print_major_deprecations!

      if groups.empty?
        # Load all groups, but only once
        @setup = load.setup
      else
        load.setup(*groups)
      end
    end

    def require(*groups)
      setup(*groups).require(*groups)
    end

    def load
      @load ||= Runtime.new(root, definition)
    end

    def environment
      SharedHelpers.major_deprecation 2, "Bundler.environment has been removed in favor of Bundler.load"
      load
    end

    # Returns an instance of Bundler::Definition for given Gemfile and lockfile
    #
    # @param unlock [Hash, Boolean, nil] Gems that have been requested
    #   to be updated or true if all gems should be updated
    # @return [Bundler::Definition]
    def definition(unlock = nil)
      @definition = nil if unlock
      @definition ||= begin
        configure
        Definition.build(default_gemfile, default_lockfile, unlock)
      end
    end

    def frozen_bundle?
      frozen = settings[:deployment]
      frozen ||= settings[:frozen] unless feature_flag.deployment_means_frozen?
      frozen
    end

    def locked_gems
      @locked_gems ||=
        if defined?(@definition) && @definition
          definition.locked_gems
        elsif Bundler.default_lockfile.file?
          lock = Bundler.read_file(Bundler.default_lockfile)
          LockfileParser.new(lock)
        end
    end

    def ruby_scope
      "#{Bundler.rubygems.ruby_engine}/#{Bundler.rubygems.config_map[:ruby_version]}"
    end

    def user_home
      @user_home ||= begin
        home = Bundler.rubygems.user_home
        bundle_home = home ? File.join(home, ".bundle") : nil

        warning = if home.nil?
          "Your home directory is not set."
        elsif !File.directory?(home)
          "`#{home}` is not a directory."
        elsif !File.writable?(home) && (!File.directory?(bundle_home) || !File.writable?(bundle_home))
          "`#{home}` is not writable."
        end

        if warning
          Kernel.send(:require, "etc")
          user_home = tmp_home_path(Etc.getlogin, warning)
          Bundler.ui.warn "#{warning}\nBundler will use `#{user_home}' as your home directory temporarily.\n"
          user_home
        else
          Pathname.new(home)
        end
      end
    end

    def tmp_home_path(login, warning)
      login ||= "unknown"
      Kernel.send(:require, "tmpdir")
      path = Pathname.new(Dir.tmpdir).join("bundler", "home")
      SharedHelpers.filesystem_access(path) do |tmp_home_path|
        unless tmp_home_path.exist?
          tmp_home_path.mkpath
          tmp_home_path.chmod(0o777)
        end
        tmp_home_path.join(login).tap(&:mkpath)
      end
    rescue RuntimeError => e
      raise e.exception("#{warning}\nBundler also failed to create a temporary home directory at `#{path}':\n#{e}")
    end

    def user_bundle_path(dir = "home")
      env_var, fallback = case dir
                          when "home"
                            ["BUNDLE_USER_HOME", Pathname.new(user_home).join(".bundle")]
                          when "cache"
                            ["BUNDLE_USER_CACHE", user_bundle_path.join("cache")]
                          when "config"
                            ["BUNDLE_USER_CONFIG", user_bundle_path.join("config")]
                          when "plugin"
                            ["BUNDLE_USER_PLUGIN", user_bundle_path.join("plugin")]
                          else
                            raise BundlerError, "Unknown user path requested: #{dir}"
      end
      # `fallback` will already be a Pathname, but Pathname.new() is
      # idempotent so it's OK
      Pathname.new(ENV.fetch(env_var, fallback))
    end

    def user_cache
      user_bundle_path("cache")
    end

    def home
      bundle_path.join("bundler")
    end

    def install_path
      home.join("gems")
    end

    def specs_path
      bundle_path.join("specifications")
    end

    def root
      @root ||= begin
                  SharedHelpers.root
                rescue GemfileNotFound
                  bundle_dir = default_bundle_dir
                  raise GemfileNotFound, "Could not locate Gemfile or .bundle/ directory" unless bundle_dir
                  Pathname.new(File.expand_path("..", bundle_dir))
                end
    end

    def app_config_path
      if app_config = ENV["BUNDLE_APP_CONFIG"]
        Pathname.new(app_config).expand_path(root)
      else
        root.join(".bundle")
      end
    end

    def app_cache(custom_path = nil)
      path = custom_path || root
      Pathname.new(path).join(settings.app_cache_path)
    end

    def tmp(name = Process.pid.to_s)
      Kernel.send(:require, "tmpdir")
      Pathname.new(Dir.mktmpdir(["bundler", name]))
    end

    def rm_rf(path)
      FileUtils.remove_entry_secure(path) if path && File.exist?(path)
    rescue ArgumentError
      message = <<EOF
It is a security vulnerability to allow your home directory to be world-writable, and bundler can not continue.
You should probably consider fixing this issue by running `chmod o-w ~` on *nix.
Please refer to http://ruby-doc.org/stdlib-2.1.2/libdoc/fileutils/rdoc/FileUtils.html#method-c-remove_entry_secure for details.
EOF
      File.world_writable?(path) ? Bundler.ui.warn(message) : raise
      raise PathError, "Please fix the world-writable issue with your #{path} directory"
    end

    def settings
      @settings ||= Settings.new(app_config_path)
    rescue GemfileNotFound
      @settings = Settings.new(Pathname.new(".bundle").expand_path)
    end

    # @return [Hash] Environment present before Bundler was activated
    def original_env
      ORIGINAL_ENV.clone
    end

    # @deprecated Use `original_env` instead
    # @return [Hash] Environment with all bundler-related variables removed
    def clean_env
      Bundler::SharedHelpers.major_deprecation(2, "`Bundler.clean_env` has weird edge cases, use `.original_env` instead")
      env = original_env

      if env.key?("BUNDLER_ORIG_MANPATH")
        env["MANPATH"] = env["BUNDLER_ORIG_MANPATH"]
      end

      env.delete_if {|k, _| k[0, 7] == "BUNDLE_" }

      if env.key?("RUBYOPT")
        env["RUBYOPT"] = env["RUBYOPT"].sub "-rbundler/setup", ""
      end

      if env.key?("RUBYLIB")
        rubylib = env["RUBYLIB"].split(File::PATH_SEPARATOR)
        rubylib.delete(File.expand_path("..", __FILE__))
        env["RUBYLIB"] = rubylib.join(File::PATH_SEPARATOR)
      end

      env
    end

    def with_original_env
      with_env(original_env) { yield }
    end

    def with_clean_env
      with_env(clean_env) { yield }
    end

    def clean_system(*args)
      with_clean_env { Kernel.system(*args) }
    end

    def clean_exec(*args)
      with_clean_env { Kernel.exec(*args) }
    end

    def local_platform
      return Gem::Platform::RUBY if settings[:force_ruby_platform]
      Gem::Platform.local
    end

    def default_gemfile
      SharedHelpers.default_gemfile
    end

    def default_lockfile
      SharedHelpers.default_lockfile
    end

    def default_bundle_dir
      SharedHelpers.default_bundle_dir
    end

    def system_bindir
      # Gem.bindir doesn't always return the location that RubyGems will install
      # system binaries. If you put '-n foo' in your .gemrc, RubyGems will
      # install binstubs there instead. Unfortunately, RubyGems doesn't expose
      # that directory at all, so rather than parse .gemrc ourselves, we allow
      # the directory to be set as well, via `bundle config bindir foo`.
      Bundler.settings[:system_bindir] || Bundler.rubygems.gem_bindir
    end

    def use_system_gems?
      configured_bundle_path.use_system_gems?
    end

    def requires_sudo?
      return @requires_sudo if defined?(@requires_sudo_ran)

      sudo_present = which "sudo" if settings.allow_sudo?

      if sudo_present
        # the bundle path and subdirectories need to be writable for RubyGems
        # to be able to unpack and install gems without exploding
        path = bundle_path
        path = path.parent until path.exist?

        # bins are written to a different location on OS X
        bin_dir = Pathname.new(Bundler.system_bindir)
        bin_dir = bin_dir.parent until bin_dir.exist?

        # if any directory is not writable, we need sudo
        files = [path, bin_dir] | Dir[bundle_path.join("build_info/*").to_s] | Dir[bundle_path.join("*").to_s]
        unwritable_files = files.reject {|f| File.writable?(f) }
        sudo_needed = !unwritable_files.empty?
        if sudo_needed
          Bundler.ui.warn "Following files may not be writable, so sudo is needed:\n  #{unwritable_files.map(&:to_s).sort.join("\n  ")}"
        end
      end

      @requires_sudo_ran = true
      @requires_sudo = settings.allow_sudo? && sudo_present && sudo_needed
    end

    def mkdir_p(path, options = {})
      if requires_sudo? && !options[:no_sudo]
        sudo "mkdir -p '#{path}'" unless File.exist?(path)
      else
        SharedHelpers.filesystem_access(path, :write) do |p|
          FileUtils.mkdir_p(p)
        end
      end
    end

    def which(executable)
      if File.file?(executable) && File.executable?(executable)
        executable
      elsif paths = ENV["PATH"]
        quote = '"'.freeze
        paths.split(File::PATH_SEPARATOR).find do |path|
          path = path[1..-2] if path.start_with?(quote) && path.end_with?(quote)
          executable_path = File.expand_path(executable, path)
          return executable_path if File.file?(executable_path) && File.executable?(executable_path)
        end
      end
    end

    def sudo(str)
      SUDO_MUTEX.synchronize do
        prompt = "\n\n" + <<-PROMPT.gsub(/^ {6}/, "").strip + " "
        Your user account isn't allowed to install to the system RubyGems.
        You can cancel this installation and run:

            bundle install --path vendor/bundle

        to install the gems into ./vendor/bundle/, or you can enter your password
        and install the bundled gems to RubyGems using sudo.

        Password:
        PROMPT

        unless @prompted_for_sudo ||= system(%(sudo -k -p "#{prompt}" true))
          raise SudoNotPermittedError,
            "Bundler requires sudo access to install at the moment. " \
            "Try installing again, granting Bundler sudo access when prompted, or installing into a different path."
        end

        `sudo -p "#{prompt}" #{str}`
      end
    end

    def read_file(file)
      SharedHelpers.filesystem_access(file, :read) do
        File.open(file, "r:UTF-8", &:read)
      end
    end

    def load_marshal(data)
      Marshal.load(data)
    rescue StandardError => e
      raise MarshalError, "#{e.class}: #{e.message}"
    end

    def load_gemspec(file, validate = false)
      @gemspec_cache ||= {}
      key = File.expand_path(file)
      @gemspec_cache[key] ||= load_gemspec_uncached(file, validate)
      # Protect against caching side-effected gemspecs by returning a
      # new instance each time.
      @gemspec_cache[key].dup if @gemspec_cache[key]
    end

    def load_gemspec_uncached(file, validate = false)
      path = Pathname.new(file)
      contents = read_file(file)
      spec = if contents.start_with?("---") # YAML header
        eval_yaml_gemspec(path, contents)
      else
        # Eval the gemspec from its parent directory, because some gemspecs
        # depend on "./" relative paths.
        SharedHelpers.chdir(path.dirname.to_s) do
          eval_gemspec(path, contents)
        end
      end
      return unless spec
      spec.loaded_from = path.expand_path.to_s
      Bundler.rubygems.validate(spec) if validate
      spec
    end

    def clear_gemspec_cache
      @gemspec_cache = {}
    end

    def git_present?
      return @git_present if defined?(@git_present)
      @git_present = Bundler.which("git") || Bundler.which("git.exe")
    end

    def feature_flag
      @feature_flag ||= FeatureFlag.new(VERSION)
    end

    def reset!
      reset_paths!
      Plugin.reset!
      reset_rubygems!
    end

    def reset_paths!
      @bin_path = nil
      @bundler_major_version = nil
      @bundle_path = nil
      @configured = nil
      @configured_bundle_path = nil
      @definition = nil
      @load = nil
      @locked_gems = nil
      @root = nil
      @settings = nil
      @setup = nil
      @user_home = nil
    end

    def reset_rubygems!
      return unless defined?(@rubygems) && @rubygems
      rubygems.undo_replacements
      rubygems.reset
      @rubygems = nil
    end

  private

    def eval_yaml_gemspec(path, contents)
      Kernel.send(:require, "bundler/psyched_yaml")

      # If the YAML is invalid, Syck raises an ArgumentError, and Psych
      # raises a Psych::SyntaxError. See psyched_yaml.rb for more info.
      Gem::Specification.from_yaml(contents)
    rescue YamlLibrarySyntaxError, ArgumentError, Gem::EndOfYAMLException, Gem::Exception
      eval_gemspec(path, contents)
    end

    def eval_gemspec(path, contents)
      eval(contents, TOPLEVEL_BINDING.dup, path.expand_path.to_s)
    rescue ScriptError, StandardError => e
      msg = "There was an error while loading `#{path.basename}`: #{e.message}"

      if e.is_a?(LoadError) && RUBY_VERSION >= "1.9"
        msg += "\nDoes it try to require a relative path? That's been removed in Ruby 1.9"
      end

      raise GemspecError, Dsl::DSLError.new(msg, path, e.backtrace, contents)
    end

    def configure_gem_home_and_path
      configure_gem_path
      configure_gem_home
      bundle_path
    end

    def configure_gem_path(env = ENV)
      blank_home = env["GEM_HOME"].nil? || env["GEM_HOME"].empty?
      if !use_system_gems?
        # this needs to be empty string to cause
        # PathSupport.split_gem_path to only load up the
        # Bundler --path setting as the GEM_PATH.
        env["GEM_PATH"] = ""
      elsif blank_home
        possibles = [Bundler.rubygems.gem_dir, Bundler.rubygems.gem_path]
        paths = possibles.flatten.compact.uniq.reject(&:empty?)
        env["GEM_PATH"] = paths.join(File::PATH_SEPARATOR)
      end
    end

    def configure_gem_home
      Bundler::SharedHelpers.set_env "GEM_HOME", File.expand_path(bundle_path, root)
      Bundler.rubygems.clear_paths
    end

    # @param env [Hash]
    def with_env(env)
      backup = ENV.to_hash
      ENV.replace(env)
      yield
    ensure
      ENV.replace(backup)
    end
  end
end
