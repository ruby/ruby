# frozen_string_literal: true

require_relative "vendored_thor"

module Bundler
  class CLI < Thor
    require_relative "cli/common"

    package_name "Bundler"

    AUTO_INSTALL_CMDS = %w[show binstubs outdated exec open console licenses clean].freeze
    PARSEABLE_COMMANDS = %w[
      check config help exec platform show version
    ].freeze

    def self.start(*)
      super
    rescue Exception => e # rubocop:disable Lint/RescueException
      Bundler.ui = UI::Shell.new
      raise e
    ensure
      Bundler::SharedHelpers.print_major_deprecations!
    end

    def self.dispatch(*)
      super do |i|
        i.send(:print_command)
        i.send(:warn_on_outdated_bundler)
      end
    end

    def initialize(*args)
      super

      custom_gemfile = options[:gemfile] || Bundler.settings[:gemfile]
      if custom_gemfile && !custom_gemfile.empty?
        Bundler::SharedHelpers.set_env "BUNDLE_GEMFILE", File.expand_path(custom_gemfile)
        Bundler.reset_paths!
      end

      Bundler.settings.set_command_option_if_given :retry, options[:retry]

      current_cmd = args.last[:current_command].name
      auto_install if AUTO_INSTALL_CMDS.include?(current_cmd)
    rescue UnknownArgumentError => e
      raise InvalidOption, e.message
    ensure
      self.options ||= {}
      unprinted_warnings = Bundler.ui.unprinted_warnings
      Bundler.ui = UI::Shell.new(options)
      Bundler.ui.level = "debug" if options["verbose"]
      unprinted_warnings.each {|w| Bundler.ui.warn(w) }

      if ENV["RUBYGEMS_GEMDEPS"] && !ENV["RUBYGEMS_GEMDEPS"].empty?
        Bundler.ui.warn(
          "The RUBYGEMS_GEMDEPS environment variable is set. This enables RubyGems' " \
          "experimental Gemfile mode, which may conflict with Bundler and cause unexpected errors. " \
          "To remove this warning, unset RUBYGEMS_GEMDEPS.", :wrap => true
        )
      end
    end

    check_unknown_options!(:except => [:config, :exec])
    stop_on_unknown_option! :exec

    desc "cli_help", "Prints a summary of bundler commands", :hide => true
    def cli_help
      version
      Bundler.ui.info "\n"

      primary_commands = ["install", "update",
                          Bundler.feature_flag.bundler_3_mode? ? "cache" : "package",
                          "exec", "config", "help"]

      list = self.class.printable_commands(true)
      by_name = list.group_by {|name, _message| name.match(/^bundle (\w+)/)[1] }
      utilities = by_name.keys.sort - primary_commands
      primary_commands.map! {|name| (by_name[name] || raise("no primary command #{name}")).first }
      utilities.map! {|name| by_name[name].first }

      shell.say "Bundler commands:\n\n"

      shell.say "  Primary commands:\n"
      shell.print_table(primary_commands, :indent => 4, :truncate => true)
      shell.say
      shell.say "  Utilities:\n"
      shell.print_table(utilities, :indent => 4, :truncate => true)
      shell.say
      self.class.send(:class_options_help, shell)
    end
    default_task(Bundler.feature_flag.default_cli_command)

    class_option "no-color", :type => :boolean, :desc => "Disable colorization in output"
    class_option "retry",    :type => :numeric, :aliases => "-r", :banner => "NUM",
                             :desc => "Specify the number of times you wish to attempt network commands"
    class_option "verbose", :type => :boolean, :desc => "Enable verbose output mode", :aliases => "-V"

    def help(cli = nil)
      case cli
      when "gemfile" then command = "gemfile"
      when nil       then command = "bundle"
      else command = "bundle-#{cli}"
      end

      man_path  = File.expand_path("../../../man", __FILE__)
      man_pages = Hash[Dir.glob(File.join(man_path, "*")).grep(/.*\.\d*\Z/).collect do |f|
        [File.basename(f, ".*"), f]
      end]

      if man_pages.include?(command)
        if Bundler.which("man") && man_path !~ %r{^file:/.+!/META-INF/jruby.home/.+}
          Kernel.exec "man #{man_pages[command]}"
        else
          puts File.read("#{man_path}/#{File.basename(man_pages[command])}.txt")
        end
      elsif command_path = Bundler.which("bundler-#{cli}")
        Kernel.exec(command_path, "--help")
      else
        super
      end
    end

    def self.handle_no_command_error(command, has_namespace = $thor_runner)
      if Bundler.feature_flag.plugins? && Bundler::Plugin.command?(command)
        return Bundler::Plugin.exec_command(command, ARGV[1..-1])
      end

      return super unless command_path = Bundler.which("bundler-#{command}")

      Kernel.exec(command_path, *ARGV[1..-1])
    end

    desc "init [OPTIONS]", "Generates a Gemfile into the current working directory"
    long_desc <<-D
      Init generates a default Gemfile in the current working directory. When adding a
      Gemfile to a gem with a gemspec, the --gemspec option will automatically add each
      dependency listed in the gemspec file to the newly created Gemfile.
    D
    method_option "gemspec", :type => :string, :banner => "Use the specified .gemspec to create the Gemfile"
    def init
      require_relative "cli/init"
      Init.new(options.dup).run
    end

    desc "check [OPTIONS]", "Checks if the dependencies listed in Gemfile are satisfied by currently installed gems"
    long_desc <<-D
      Check searches the local machine for each of the gems requested in the Gemfile. If
      all gems are found, Bundler prints a success message and exits with a status of 0.
      If not, the first missing gem is listed and Bundler exits status 1.
    D
    method_option "dry-run", :type => :boolean, :default => false, :banner =>
      "Lock the Gemfile"
    method_option "gemfile", :type => :string, :banner =>
      "Use the specified gemfile instead of Gemfile"
    method_option "path", :type => :string, :banner =>
      "Specify a different path than the system default ($BUNDLE_PATH or $GEM_HOME).#{" Bundler will remember this value for future installs on this machine" unless Bundler.feature_flag.forget_cli_options?}"
    map "c" => "check"
    def check
      require_relative "cli/check"
      Check.new(options).run
    end

    desc "remove [GEM [GEM ...]]", "Removes gems from the Gemfile"
    long_desc <<-D
      Removes the given gems from the Gemfile while ensuring that the resulting Gemfile is still valid. If the gem is not found, Bundler prints a error message and if gem could not be removed due to any reason Bundler will display a warning.
    D
    method_option "install", :type => :boolean, :banner =>
      "Runs 'bundle install' after removing the gems from the Gemfile"
    def remove(*gems)
      require_relative "cli/remove"
      Remove.new(gems, options).run
    end

    desc "install [OPTIONS]", "Install the current environment to the system"
    long_desc <<-D
      Install will install all of the gems in the current bundle, making them available
      for use. In a freshly checked out repository, this command will give you the same
      gem versions as the last person who updated the Gemfile and ran `bundle update`.

      Passing [DIR] to install (e.g. vendor) will cause the unpacked gems to be installed
      into the [DIR] directory rather than into system gems.

      If the bundle has already been installed, bundler will tell you so and then exit.
    D
    method_option "binstubs", :type => :string, :lazy_default => "bin", :banner =>
      "Generate bin stubs for bundled gems to ./bin"
    method_option "clean", :type => :boolean, :banner =>
      "Run bundle clean automatically after install"
    method_option "deployment", :type => :boolean, :banner =>
      "Install using defaults tuned for deployment environments"
    method_option "frozen", :type => :boolean, :banner =>
      "Do not allow the Gemfile.lock to be updated after this install"
    method_option "full-index", :type => :boolean, :banner =>
      "Fall back to using the single-file index of all gems"
    method_option "gemfile", :type => :string, :banner =>
      "Use the specified gemfile instead of Gemfile"
    method_option "jobs", :aliases => "-j", :type => :numeric, :banner =>
      "Specify the number of jobs to run in parallel"
    method_option "local", :type => :boolean, :banner =>
      "Do not attempt to fetch gems remotely and use the gem cache instead"
    method_option "no-cache", :type => :boolean, :banner =>
      "Don't update the existing gem cache."
    method_option "redownload", :type => :boolean, :aliases => "--force", :banner =>
      "Force downloading every gem."
    method_option "no-prune", :type => :boolean, :banner =>
      "Don't remove stale gems from the cache."
    method_option "path", :type => :string, :banner =>
      "Specify a different path than the system default ($BUNDLE_PATH or $GEM_HOME). Bundler will remember this value for future installs on this machine"
    method_option "quiet", :type => :boolean, :banner =>
      "Only output warnings and errors."
    method_option "shebang", :type => :string, :banner =>
      "Specify a different shebang executable name than the default (usually 'ruby')"
    method_option "standalone", :type => :array, :lazy_default => [], :banner =>
      "Make a bundle that can work without the Bundler runtime"
    method_option "system", :type => :boolean, :banner =>
      "Install to the system location ($BUNDLE_PATH or $GEM_HOME) even if the bundle was previously installed somewhere else for this application"
    method_option "trust-policy", :alias => "P", :type => :string, :banner =>
      "Gem trust policy (like gem install -P). Must be one of " +
        Bundler.rubygems.security_policy_keys.join("|")
    method_option "without", :type => :array, :banner =>
      "Exclude gems that are part of the specified named group."
    method_option "with", :type => :array, :banner =>
      "Include gems that are part of the specified named group."
    map "i" => "install"
    def install
      SharedHelpers.major_deprecation(2, "The `--force` option has been renamed to `--redownload`") if ARGV.include?("--force")

      %w[clean deployment frozen no-cache no-prune path shebang system without with].each do |option|
        remembered_flag_deprecation(option)
      end

      require_relative "cli/install"
      Bundler.settings.temporary(:no_install => false) do
        Install.new(options.dup).run
      end
    end

    desc "update [OPTIONS]", "Update the current environment"
    long_desc <<-D
      Update will install the newest versions of the gems listed in the Gemfile. Use
      update when you have changed the Gemfile, or if you want to get the newest
      possible versions of the gems in the bundle.
    D
    method_option "full-index", :type => :boolean, :banner =>
      "Fall back to using the single-file index of all gems"
    method_option "gemfile", :type => :string, :banner =>
      "Use the specified gemfile instead of Gemfile"
    method_option "group", :aliases => "-g", :type => :array, :banner =>
      "Update a specific group"
    method_option "jobs", :aliases => "-j", :type => :numeric, :banner =>
      "Specify the number of jobs to run in parallel"
    method_option "local", :type => :boolean, :banner =>
      "Do not attempt to fetch gems remotely and use the gem cache instead"
    method_option "quiet", :type => :boolean, :banner =>
      "Only output warnings and errors."
    method_option "source", :type => :array, :banner =>
      "Update a specific source (and all gems associated with it)"
    method_option "redownload", :type => :boolean, :aliases => "--force", :banner =>
      "Force downloading every gem."
    method_option "ruby", :type => :boolean, :banner =>
      "Update ruby specified in Gemfile.lock"
    method_option "bundler", :type => :string, :lazy_default => "> 0.a", :banner =>
      "Update the locked version of bundler"
    method_option "patch", :type => :boolean, :banner =>
      "Prefer updating only to next patch version"
    method_option "minor", :type => :boolean, :banner =>
      "Prefer updating only to next minor version"
    method_option "major", :type => :boolean, :banner =>
      "Prefer updating to next major version (default)"
    method_option "strict", :type => :boolean, :banner =>
      "Do not allow any gem to be updated past latest --patch | --minor | --major"
    method_option "conservative", :type => :boolean, :banner =>
      "Use bundle install conservative update behavior and do not allow shared dependencies to be updated."
    method_option "all", :type => :boolean, :banner =>
      "Update everything."
    def update(*gems)
      SharedHelpers.major_deprecation(2, "The `--force` option has been renamed to `--redownload`") if ARGV.include?("--force")
      require_relative "cli/update"
      Bundler.settings.temporary(:no_install => false) do
        Update.new(options, gems).run
      end
    end

    unless Bundler.feature_flag.bundler_3_mode?
      desc "show GEM [OPTIONS]", "Shows all gems that are part of the bundle, or the path to a given gem"
      long_desc <<-D
        Show lists the names and versions of all gems that are required by your Gemfile.
        Calling show with [GEM] will list the exact location of that gem on your machine.
      D
      method_option "paths", :type => :boolean,
                             :banner => "List the paths of all gems that are required by your Gemfile."
      method_option "outdated", :type => :boolean,
                                :banner => "Show verbose output including whether gems are outdated."
      def show(gem_name = nil)
        if ARGV[0] == "show"
          rest = ARGV[1..-1]

          if flag = rest.find{|arg| ["--verbose", "--outdated"].include?(arg) }
            Bundler::SharedHelpers.major_deprecation(2, "the `#{flag}` flag to `bundle show` was undocumented and will be removed without replacement")
          else
            new_command = rest.find {|arg| !arg.start_with?("--") } ? "info" : "list"

            new_arguments = rest.map do |arg|
              next arg if arg != "--paths"
              next "--path" if new_command == "info"
            end

            old_argv = ARGV.join(" ")
            new_argv = [new_command, *new_arguments.compact].join(" ")

            Bundler::SharedHelpers.major_deprecation(2, "use `bundle #{new_argv}` instead of `bundle #{old_argv}`")
          end
        end
        require_relative "cli/show"
        Show.new(options, gem_name).run
      end
    end

    desc "list", "List all gems in the bundle"
    method_option "name-only", :type => :boolean, :banner => "print only the gem names"
    method_option "only-group", :type => :string, :banner => "print gems from a particular group"
    method_option "without-group", :type => :string, :banner => "print all gems except from a group"
    method_option "paths", :type => :boolean, :banner => "print the path to each gem in the bundle"
    def list
      require_relative "cli/list"
      List.new(options).run
    end

    map %w[ls] => "list"

    desc "info GEM [OPTIONS]", "Show information for the given gem"
    method_option "path", :type => :boolean, :banner => "Print full path to gem"
    def info(gem_name)
      require_relative "cli/info"
      Info.new(options, gem_name).run
    end

    desc "binstubs GEM [OPTIONS]", "Install the binstubs of the listed gem"
    long_desc <<-D
      Generate binstubs for executables in [GEM]. Binstubs are put into bin,
      or the --binstubs directory if one has been set. Calling binstubs with [GEM [GEM]]
      will create binstubs for all given gems.
    D
    method_option "force", :type => :boolean, :default => false, :banner =>
      "Overwrite existing binstubs if they exist"
    method_option "path", :type => :string, :lazy_default => "bin", :banner =>
      "Binstub destination directory (default bin)"
    method_option "shebang", :type => :string, :banner =>
      "Specify a different shebang executable name than the default (usually 'ruby')"
    method_option "standalone", :type => :boolean, :banner =>
      "Make binstubs that can work without the Bundler runtime"
    method_option "all", :type => :boolean, :banner =>
      "Install binstubs for all gems"
    def binstubs(*gems)
      require_relative "cli/binstubs"
      Binstubs.new(options, gems).run
    end

    desc "add GEM VERSION", "Add gem to Gemfile and run bundle install"
    long_desc <<-D
      Adds the specified gem to Gemfile (if valid) and run 'bundle install' in one step.
    D
    method_option "version", :aliases => "-v", :type => :string
    method_option "group", :aliases => "-g", :type => :string
    method_option "source", :aliases => "-s", :type => :string
    method_option "git", :type => :string
    method_option "branch", :type => :string
    method_option "skip-install", :type => :boolean, :banner =>
      "Adds gem to the Gemfile but does not install it"
    method_option "optimistic", :type => :boolean, :banner => "Adds optimistic declaration of version to gem"
    method_option "strict", :type => :boolean, :banner => "Adds strict declaration of version to gem"
    def add(*gems)
      require_relative "cli/add"
      Add.new(options.dup, gems).run
    end

    desc "outdated GEM [OPTIONS]", "List installed gems with newer versions available"
    long_desc <<-D
      Outdated lists the names and versions of gems that have a newer version available
      in the given source. Calling outdated with [GEM [GEM]] will only check for newer
      versions of the given gems. Prerelease gems are ignored by default. If your gems
      are up to date, Bundler will exit with a status of 0. Otherwise, it will exit 1.

      For more information on patch level options (--major, --minor, --patch,
      --update-strict) see documentation on the same options on the update command.
    D
    method_option "group", :type => :string, :banner => "List gems from a specific group"
    method_option "groups", :type => :boolean, :banner => "List gems organized by groups"
    method_option "local", :type => :boolean, :banner =>
      "Do not attempt to fetch gems remotely and use the gem cache instead"
    method_option "pre", :type => :boolean, :banner => "Check for newer pre-release gems"
    method_option "source", :type => :array, :banner => "Check against a specific source"
    strict_is_update = Bundler.feature_flag.forget_cli_options?
    method_option "filter-strict", :type => :boolean, :aliases => strict_is_update ? [] : %w[--strict], :banner =>
      "Only list newer versions allowed by your Gemfile requirements"
    method_option "update-strict", :type => :boolean, :aliases => strict_is_update ? %w[--strict] : [], :banner =>
      "Strict conservative resolution, do not allow any gem to be updated past latest --patch | --minor | --major"
    method_option "minor", :type => :boolean, :banner => "Prefer updating only to next minor version"
    method_option "major", :type => :boolean, :banner => "Prefer updating to next major version (default)"
    method_option "patch", :type => :boolean, :banner => "Prefer updating only to next patch version"
    method_option "filter-major", :type => :boolean, :banner => "Only list major newer versions"
    method_option "filter-minor", :type => :boolean, :banner => "Only list minor newer versions"
    method_option "filter-patch", :type => :boolean, :banner => "Only list patch newer versions"
    method_option "parseable", :aliases => "--porcelain", :type => :boolean, :banner =>
      "Use minimal formatting for more parseable output"
    method_option "only-explicit", :type => :boolean, :banner =>
      "Only list gems specified in your Gemfile, not their dependencies"
    def outdated(*gems)
      require_relative "cli/outdated"
      Outdated.new(options, gems).run
    end

    desc "#{Bundler.feature_flag.bundler_3_mode? ? :cache : :package} [OPTIONS]", "Locks and then caches all of the gems into vendor/cache"
    unless Bundler.feature_flag.cache_all?
      method_option "all",  :type => :boolean,
                            :banner => "Include all sources (including path and git)."
    end
    method_option "all-platforms", :type => :boolean, :banner => "Include gems for all platforms present in the lockfile, not only the current one"
    method_option "cache-path", :type => :string, :banner =>
      "Specify a different cache path than the default (vendor/cache)."
    method_option "gemfile", :type => :string, :banner => "Use the specified gemfile instead of Gemfile"
    method_option "no-install", :type => :boolean, :banner => "Don't install the gems, only the package."
    method_option "no-prune", :type => :boolean, :banner => "Don't remove stale gems from the cache."
    method_option "path", :type => :string, :banner =>
      "Specify a different path than the system default ($BUNDLE_PATH or $GEM_HOME). Bundler will remember this value for future installs on this machine"
    method_option "quiet", :type => :boolean, :banner => "Only output warnings and errors."
    method_option "frozen", :type => :boolean, :banner =>
      "Do not allow the Gemfile.lock to be updated after this package operation's install"
    long_desc <<-D
      The package command will copy the .gem files for every gem in the bundle into the
      directory ./vendor/cache. If you then check that directory into your source
      control repository, others who check out your source will be able to install the
      bundle without having to download any additional gems.
    D
    def package
      require_relative "cli/package"
      Package.new(options).run
    end
    map %w[cache pack] => :package

    desc "exec [OPTIONS]", "Run the command in context of the bundle"
    method_option :keep_file_descriptors, :type => :boolean, :default => false
    method_option :gemfile, :type => :string, :required => false
    long_desc <<-D
      Exec runs a command, providing it access to the gems in the bundle. While using
      bundle exec you can require and call the bundled gems as if they were installed
      into the system wide RubyGems repository.
    D
    map "e" => "exec"
    def exec(*args)
      require_relative "cli/exec"
      Exec.new(options, args).run
    end

    desc "config NAME [VALUE]", "Retrieve or set a configuration value"
    long_desc <<-D
      Retrieves or sets a configuration value. If only one parameter is provided, retrieve the value. If two parameters are provided, replace the
      existing value with the newly provided one.

      By default, setting a configuration value sets it for all projects
      on the machine.

      If a global setting is superceded by local configuration, this command
      will show the current value, as well as any superceded values and
      where they were specified.
    D
    require_relative "cli/config"
    subcommand "config", Config

    desc "open GEM", "Opens the source directory of the given bundled gem"
    def open(name)
      require_relative "cli/open"
      Open.new(options, name).run
    end

    unless Bundler.feature_flag.bundler_3_mode?
      desc "console [GROUP]", "Opens an IRB session with the bundle pre-loaded"
      def console(group = nil)
        require_relative "cli/console"
        Console.new(options, group).run
      end
    end

    desc "version", "Prints the bundler's version information"
    def version
      cli_help = current_command.name == "cli_help"
      if cli_help || ARGV.include?("version")
        build_info = " (#{BuildMetadata.built_at} commit #{BuildMetadata.git_commit_sha})"
      end

      if !cli_help && Bundler.feature_flag.print_only_version_number?
        Bundler.ui.info "#{Bundler::VERSION}#{build_info}"
      else
        Bundler.ui.info "Bundler version #{Bundler::VERSION}#{build_info}"
      end
    end
    map %w[-v --version] => :version

    desc "licenses", "Prints the license of all gems in the bundle"
    def licenses
      Bundler.load.specs.sort_by {|s| s.license.to_s }.reverse_each do |s|
        gem_name = s.name
        license  = s.license || s.licenses

        if license.empty?
          Bundler.ui.warn "#{gem_name}: Unknown"
        else
          Bundler.ui.info "#{gem_name}: #{license}"
        end
      end
    end

    unless Bundler.feature_flag.bundler_3_mode?
      desc "viz [OPTIONS]", "Generates a visual dependency graph", :hide => true
      long_desc <<-D
        Viz generates a PNG file of the current Gemfile as a dependency graph.
        Viz requires the ruby-graphviz gem (and its dependencies).
        The associated gems must also be installed via 'bundle install'.
      D
      method_option :file, :type => :string, :default => "gem_graph", :aliases => "-f", :desc => "The name to use for the generated file. see format option"
      method_option :format, :type => :string, :default => "png", :aliases => "-F", :desc => "This is output format option. Supported format is png, jpg, svg, dot ..."
      method_option :requirements, :type => :boolean, :default => false, :aliases => "-R", :desc => "Set to show the version of each required dependency."
      method_option :version, :type => :boolean, :default => false, :aliases => "-v", :desc => "Set to show each gem version."
      method_option :without, :type => :array, :default => [], :aliases => "-W", :banner => "GROUP[ GROUP...]", :desc => "Exclude gems that are part of the specified named group."
      def viz
        SharedHelpers.major_deprecation 2, "The `viz` command has been moved to the `bundle-viz` gem, see https://github.com/bundler/bundler-viz"
        require_relative "cli/viz"
        Viz.new(options.dup).run
      end
    end

    old_gem = instance_method(:gem)

    desc "gem NAME [OPTIONS]", "Creates a skeleton for creating a rubygem"
    method_option :exe, :type => :boolean, :default => false, :aliases => ["--bin", "-b"], :desc => "Generate a binary executable for your library."
    method_option :coc, :type => :boolean, :desc => "Generate a code of conduct file. Set a default with `bundle config set gem.coc true`."
    method_option :edit, :type => :string, :aliases => "-e", :required => false, :banner => "EDITOR",
                         :lazy_default => [ENV["BUNDLER_EDITOR"], ENV["VISUAL"], ENV["EDITOR"]].find {|e| !e.nil? && !e.empty? },
                         :desc => "Open generated gemspec in the specified editor (defaults to $EDITOR or $BUNDLER_EDITOR)"
    method_option :ext, :type => :boolean, :default => false, :desc => "Generate the boilerplate for C extension code"
    method_option :mit, :type => :boolean, :desc => "Generate an MIT license file. Set a default with `bundle config set gem.mit true`."
    method_option :test, :type => :string, :lazy_default => "rspec", :aliases => "-t", :banner => "rspec",
                         :desc => "Generate a test directory for your library, either rspec or minitest. Set a default with `bundle config set gem.test rspec`."
    def gem(name)
    end

    commands["gem"].tap do |gem_command|
      def gem_command.run(instance, args = [])
        arity = 1 # name

        require_relative "cli/gem"
        cmd_args = args + [instance]
        cmd_args.unshift(instance.options)

        cmd = begin
          Gem.new(*cmd_args)
        rescue ArgumentError => e
          instance.class.handle_argument_error(self, e, args, arity)
        end

        cmd.run
      end
    end

    undef_method(:gem)
    define_method(:gem, old_gem)
    private :gem

    def self.source_root
      File.expand_path(File.join(File.dirname(__FILE__), "templates"))
    end

    desc "clean [OPTIONS]", "Cleans up unused gems in your bundler directory", :hide => true
    method_option "dry-run", :type => :boolean, :default => false, :banner =>
      "Only print out changes, do not clean gems"
    method_option "force", :type => :boolean, :default => false, :banner =>
      "Forces clean even if --path is not set"
    def clean
      require_relative "cli/clean"
      Clean.new(options.dup).run
    end

    desc "platform [OPTIONS]", "Displays platform compatibility information"
    method_option "ruby", :type => :boolean, :default => false, :banner =>
      "only display ruby related platform information"
    def platform
      require_relative "cli/platform"
      Platform.new(options).run
    end

    desc "inject GEM VERSION", "Add the named gem, with version requirements, to the resolved Gemfile", :hide => true
    method_option "source", :type => :string, :banner =>
     "Install gem from the given source"
    method_option "group", :type => :string, :banner =>
     "Install gem into a bundler group"
    def inject(name, version)
      SharedHelpers.major_deprecation 2, "The `inject` command has been replaced by the `add` command"
      require_relative "cli/inject"
      Inject.new(options.dup, name, version).run
    end

    desc "lock", "Creates a lockfile without installing"
    method_option "update", :type => :array, :lazy_default => true, :banner =>
      "ignore the existing lockfile, update all gems by default, or update list of given gems"
    method_option "local", :type => :boolean, :default => false, :banner =>
      "do not attempt to fetch remote gemspecs and use the local gem cache only"
    method_option "print", :type => :boolean, :default => false, :banner =>
      "print the lockfile to STDOUT instead of writing to the file system"
    method_option "gemfile", :type => :string, :banner =>
      "Use the specified gemfile instead of Gemfile"
    method_option "lockfile", :type => :string, :default => nil, :banner =>
      "the path the lockfile should be written to"
    method_option "full-index", :type => :boolean, :default => false, :banner =>
      "Fall back to using the single-file index of all gems"
    method_option "add-platform", :type => :array, :default => [], :banner =>
      "Add a new platform to the lockfile"
    method_option "remove-platform", :type => :array, :default => [], :banner =>
      "Remove a platform from the lockfile"
    method_option "patch", :type => :boolean, :banner =>
      "If updating, prefer updating only to next patch version"
    method_option "minor", :type => :boolean, :banner =>
      "If updating, prefer updating only to next minor version"
    method_option "major", :type => :boolean, :banner =>
      "If updating, prefer updating to next major version (default)"
    method_option "strict", :type => :boolean, :banner =>
      "If updating, do not allow any gem to be updated past latest --patch | --minor | --major"
    method_option "conservative", :type => :boolean, :banner =>
      "If updating, use bundle install conservative update behavior and do not allow shared dependencies to be updated"
    def lock
      require_relative "cli/lock"
      Lock.new(options).run
    end

    desc "env", "Print information about the environment Bundler is running under"
    def env
      Env.write($stdout)
    end

    desc "doctor [OPTIONS]", "Checks the bundle for common problems"
    long_desc <<-D
      Doctor scans the OS dependencies of each of the gems requested in the Gemfile. If
      missing dependencies are detected, Bundler prints them and exits status 1.
      Otherwise, Bundler prints a success message and exits with a status of 0.
    D
    method_option "gemfile", :type => :string, :banner =>
      "Use the specified gemfile instead of Gemfile"
    method_option "quiet", :type => :boolean, :banner =>
        "Only output warnings and errors."
    def doctor
      require_relative "cli/doctor"
      Doctor.new(options).run
    end

    desc "issue", "Learn how to report an issue in Bundler"
    def issue
      require_relative "cli/issue"
      Issue.new.run
    end

    desc "pristine [GEMS...]", "Restores installed gems to pristine condition"
    long_desc <<-D
      Restores installed gems to pristine condition from files located in the
      gem cache. Gems installed from a git repository will be issued `git
      checkout --force`.
    D
    def pristine(*gems)
      require_relative "cli/pristine"
      Pristine.new(gems).run
    end

    if Bundler.feature_flag.plugins?
      require_relative "cli/plugin"
      desc "plugin", "Manage the bundler plugins"
      subcommand "plugin", Plugin
    end

    # Reformat the arguments passed to bundle that include a --help flag
    # into the corresponding `bundle help #{command}` call
    def self.reformatted_help_args(args)
      bundler_commands = all_commands.keys
      help_flags = %w[--help -h]
      exec_commands = %w[e ex exe exec]
      help_used = args.index {|a| help_flags.include? a }
      exec_used = args.index {|a| exec_commands.include? a }
      command = args.find {|a| bundler_commands.include? a }
      if exec_used && help_used
        if exec_used + help_used == 1
          %w[help exec]
        else
          args
        end
      elsif help_used
        args = args.dup
        args.delete_at(help_used)
        ["help", command || args].flatten.compact
      else
        args
      end
    end

  private

    # Automatically invoke `bundle install` and resume if
    # Bundler.settings[:auto_install] exists. This is set through config cmd
    # `bundle config set auto_install 1`.
    #
    # Note that this method `nil`s out the global Definition object, so it
    # should be called first, before you instantiate anything like an
    # `Installer` that'll keep a reference to the old one instead.
    def auto_install
      return unless Bundler.settings[:auto_install]

      begin
        Bundler.definition.specs
      rescue GemNotFound
        Bundler.ui.info "Automatically installing missing gems."
        Bundler.reset!
        invoke :install, []
        Bundler.reset!
      end
    end

    def current_command
      _, _, config = @_initializer
      config[:current_command]
    end

    def print_command
      return unless Bundler.ui.debug?
      cmd = current_command
      command_name = cmd.name
      return if PARSEABLE_COMMANDS.include?(command_name)
      command = ["bundle", command_name] + args
      options_to_print = options.dup
      options_to_print.delete_if do |k, v|
        next unless o = cmd.options[k]
        o.default == v
      end
      command << Thor::Options.to_switches(options_to_print.sort_by(&:first)).strip
      command.reject!(&:empty?)
      Bundler.ui.info "Running `#{command * " "}` with bundler #{Bundler::VERSION}"
    end

    def warn_on_outdated_bundler
      return if Bundler.settings[:disable_version_check]

      command_name = current_command.name
      return if PARSEABLE_COMMANDS.include?(command_name)

      return unless SharedHelpers.md5_available?

      latest = Fetcher::CompactIndex.
               new(nil, Source::Rubygems::Remote.new(URI("https://rubygems.org")), nil).
               send(:compact_index_client).
               instance_variable_get(:@cache).
               dependencies("bundler").
               map {|d| Gem::Version.new(d.first) }.
               max
      return unless latest

      current = Gem::Version.new(VERSION)
      return if current >= latest
      latest_installed = Bundler.rubygems.find_name("bundler").map(&:version).max

      installation = "To install the latest version, run `gem install bundler#{" --pre" if latest.prerelease?}`"
      if latest_installed && latest_installed > current
        suggestion = "To update to the most recent installed version (#{latest_installed}), run `bundle update --bundler`"
        suggestion = "#{installation}\n#{suggestion}" if latest_installed < latest
      else
        suggestion = installation
      end

      Bundler.ui.warn "The latest bundler is #{latest}, but you are currently running #{current}.\n#{suggestion}"
    rescue RuntimeError
      nil
    end

    def remembered_flag_deprecation(name)
      option = current_command.options[name]
      flag_name = option.switch_name

      name_index = ARGV.find {|arg| flag_name == arg }
      return unless name_index

      value = options[name]
      value = value.join(" ").to_s if option.type == :array

      Bundler::SharedHelpers.major_deprecation 2,\
        "The `#{flag_name}` flag is deprecated because it relies on being " \
        "remembered accross bundler invokations, which bundler will no longer " \
        "do in future versions. Instead please use `bundle config #{name} " \
        "'#{value}'`, and stop using this flag"
    end
  end
end
