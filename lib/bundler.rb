# frozen_string_literal: true
require "fileutils"
require "pathname"
require "rbconfig"
require "thread"
require "tmpdir"

require "bundler/errors"
require "bundler/environment_preserver"
require "bundler/plugin"
require "bundler/rubygems_ext"
require "bundler/rubygems_integration"
require "bundler/version"
require "bundler/constants"
require "bundler/current_ruby"

module Bundler
  environment_preserver = EnvironmentPreserver.new(ENV, %w(PATH GEM_PATH))
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

  class << self
    attr_writer :bundle_path

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
      @bundle_path ||= Pathname.new(settings.path).expand_path(root)
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
      SharedHelpers.major_deprecation "Bundler.environment has been removed in favor of Bundler.load"
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
        warning = "Your home directory is not set properly:"
        if home.nil?
          warning += "\n * It is not set at all"
        elsif !File.directory?(home)
          warning += "\n * `#{home}` is not a directory"
        elsif !File.writable?(home)
          warning += "\n * `#{home}` is not writable"
        else
          return @user_home = Pathname.new(home)
        end

        login = Etc.getlogin || "unknown"

        tmp_home = Pathname.new(Dir.tmpdir).join("bundler", "home", login)
        begin
          SharedHelpers.filesystem_access(tmp_home, :write) do |p|
            FileUtils.mkdir_p(p)
          end
        rescue => e
          warning += "\n\nBundler also failed to create a temporary home directory at `#{tmp_home}`:\n#{e}"
          raise warning
        end

        warning += "\n\nBundler will use `#{tmp_home}` as your home directory temporarily"

        Bundler.ui.warn(warning)
        tmp_home
      end
    end

    def user_bundle_path
      Pathname.new(user_home).join(".bundle")
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

    def cache
      bundle_path.join("cache/bundler")
    end

    def user_cache
      user_bundle_path.join("cache")
    end

    def root
      @root ||= begin
                  default_gemfile.dirname.expand_path
                rescue GemfileNotFound
                  bundle_dir = default_bundle_dir
                  raise GemfileNotFound, "Could not locate Gemfile or .bundle/ directory" unless bundle_dir
                  Pathname.new(File.expand_path("..", bundle_dir))
                end
    end

    def app_config_path
      if ENV["BUNDLE_APP_CONFIG"]
        Pathname.new(ENV["BUNDLE_APP_CONFIG"]).expand_path(root)
      else
        root.join(".bundle")
      end
    end

    def app_cache(custom_path = nil)
      path = custom_path || root
      path.join(settings.app_cache_path)
    end

    def tmp(name = Process.pid.to_s)
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
      Bundler::SharedHelpers.major_deprecation("`Bundler.clean_env` has weird edge cases, use `.original_env` instead")
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
      # Gem.bindir doesn't always return the location that Rubygems will install
      # system binaries. If you put '-n foo' in your .gemrc, Rubygems will
      # install binstubs there instead. Unfortunately, Rubygems doesn't expose
      # that directory at all, so rather than parse .gemrc ourselves, we allow
      # the directory to be set as well, via `bundle config bindir foo`.
      Bundler.settings[:system_bindir] || Bundler.rubygems.gem_bindir
    end

    def requires_sudo?
      return @requires_sudo if defined?(@requires_sudo_ran)

      sudo_present = which "sudo" if settings.allow_sudo?

      if sudo_present
        # the bundle path and subdirectories need to be writable for Rubygems
        # to be able to unpack and install gems without exploding
        path = bundle_path
        path = path.parent until path.exist?

        # bins are written to a different location on OS X
        bin_dir = Pathname.new(Bundler.system_bindir)
        bin_dir = bin_dir.parent until bin_dir.exist?

        # if any directory is not writable, we need sudo
        files = [path, bin_dir] | Dir[path.join("build_info/*").to_s] | Dir[path.join("*").to_s]
        sudo_needed = files.any? {|f| !File.writable?(f) }
      end

      @requires_sudo_ran = true
      @requires_sudo = settings.allow_sudo? && sudo_present && sudo_needed
    end

    def mkdir_p(path)
      if requires_sudo?
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
      File.open(file, "rb", &:read)
    end

    def load_marshal(data)
      Marshal.load(data)
    rescue => e
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
      # Eval the gemspec from its parent directory, because some gemspecs
      # depend on "./" relative paths.
      SharedHelpers.chdir(path.dirname.to_s) do
        contents = path.read
        spec = if contents[0..2] == "---" # YAML header
          eval_yaml_gemspec(path, contents)
        else
          eval_gemspec(path, contents)
        end
        return unless spec
        spec.loaded_from = path.expand_path.to_s
        Bundler.rubygems.validate(spec) if validate
        spec
      end
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
      @root = nil
      @settings = nil
      @definition = nil
      @setup = nil
      @load = nil
      @locked_gems = nil
      @bundle_path = nil
      @bin_path = nil
      @user_home = nil

      Plugin.reset!

      return unless defined?(@rubygems) && @rubygems
      rubygems.undo_replacements
      rubygems.reset
      @rubygems = nil
    end

  private

    def eval_yaml_gemspec(path, contents)
      # If the YAML is invalid, Syck raises an ArgumentError, and Psych
      # raises a Psych::SyntaxError. See psyched_yaml.rb for more info.
      Gem::Specification.from_yaml(contents)
    rescue YamlLibrarySyntaxError, ArgumentError, Gem::EndOfYAMLException, Gem::Exception
      eval_gemspec(path, contents)
    end

    def eval_gemspec(path, contents)
      eval(contents, TOPLEVEL_BINDING, path.expand_path.to_s)
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

    def configure_gem_path(env = ENV, settings = self.settings)
      blank_home = env["GEM_HOME"].nil? || env["GEM_HOME"].empty?
      if settings[:disable_shared_gems]
        # this needs to be empty string to cause
        # PathSupport.split_gem_path to only load up the
        # Bundler --path setting as the GEM_PATH.
        env["GEM_PATH"] = ""
      elsif blank_home || Bundler.rubygems.gem_dir != bundle_path.to_s
        possibles = [Bundler.rubygems.gem_dir, Bundler.rubygems.gem_path]
        paths = possibles.flatten.compact.uniq.reject(&:empty?)
        env["GEM_PATH"] = paths.join(File::PATH_SEPARATOR)
      end
    end

    def configure_gem_home
      # TODO: This mkdir_p is only needed for JRuby <= 1.5 and should go away (GH #602)
      begin
        FileUtils.mkdir_p bundle_path.to_s
      rescue
        nil
      end

      ENV["GEM_HOME"] = File.expand_path(bundle_path, root)
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
