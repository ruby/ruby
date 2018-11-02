# frozen_string_literal: true

module Bundler
  class CLI::Install
    attr_reader :options
    def initialize(options)
      @options = options
    end

    def run
      Bundler.ui.level = "error" if options[:quiet]

      warn_if_root

      normalize_groups

      Bundler::SharedHelpers.set_env "RB_USER_INSTALL", "1" if Bundler::FREEBSD

      # Disable color in deployment mode
      Bundler.ui.shell = Thor::Shell::Basic.new if options[:deployment]

      check_for_options_conflicts

      check_trust_policy

      if options[:deployment] || options[:frozen] || Bundler.frozen_bundle?
        unless Bundler.default_lockfile.exist?
          flag   = "--deployment flag" if options[:deployment]
          flag ||= "--frozen flag"     if options[:frozen]
          flag ||= "deployment setting"
          raise ProductionError, "The #{flag} requires a #{Bundler.default_lockfile.relative_path_from(SharedHelpers.pwd)}. Please make " \
                                 "sure you have checked your #{Bundler.default_lockfile.relative_path_from(SharedHelpers.pwd)} into version control " \
                                 "before deploying."
        end

        options[:local] = true if Bundler.app_cache.exist?

        if Bundler.feature_flag.deployment_means_frozen?
          Bundler.settings.set_command_option :deployment, true
        else
          Bundler.settings.set_command_option :frozen, true
        end
      end

      # When install is called with --no-deployment, disable deployment mode
      if options[:deployment] == false
        Bundler.settings.set_command_option :frozen, nil
        options[:system] = true
      end

      normalize_settings

      Bundler::Fetcher.disable_endpoint = options["full-index"]

      if options["binstubs"]
        Bundler::SharedHelpers.major_deprecation 2,
          "The --binstubs option will be removed in favor of `bundle binstubs`"
      end

      Plugin.gemfile_install(Bundler.default_gemfile) if Bundler.feature_flag.plugins?

      definition = Bundler.definition
      definition.validate_runtime!

      installer = Installer.install(Bundler.root, definition, options)
      Bundler.load.cache if Bundler.app_cache.exist? && !options["no-cache"] && !Bundler.frozen_bundle?

      Bundler.ui.confirm "Bundle complete! #{dependencies_count_for(definition)}, #{gems_installed_for(definition)}."
      Bundler::CLI::Common.output_without_groups_message

      if Bundler.use_system_gems?
        Bundler.ui.confirm "Use `bundle info [gemname]` to see where a bundled gem is installed."
      else
        absolute_path = File.expand_path(Bundler.configured_bundle_path.base_path)
        relative_path = absolute_path.sub(File.expand_path(".") + File::SEPARATOR, "." + File::SEPARATOR)
        Bundler.ui.confirm "Bundled gems are installed into `#{relative_path}`"
      end

      Bundler::CLI::Common.output_post_install_messages installer.post_install_messages

      warn_ambiguous_gems

      if CLI::Common.clean_after_install?
        require "bundler/cli/clean"
        Bundler::CLI::Clean.new(options).run
      end
    rescue GemNotFound, VersionConflict => e
      if options[:local] && Bundler.app_cache.exist?
        Bundler.ui.warn "Some gems seem to be missing from your #{Bundler.settings.app_cache_path} directory."
      end

      unless Bundler.definition.has_rubygems_remotes?
        Bundler.ui.warn <<-WARN, :wrap => true
          Your Gemfile has no gem server sources. If you need gems that are \
          not already on your machine, add a line like this to your Gemfile:
          source 'https://rubygems.org'
        WARN
      end
      raise e
    rescue Gem::InvalidSpecificationException => e
      Bundler.ui.warn "You have one or more invalid gemspecs that need to be fixed."
      raise e
    end

  private

    def warn_if_root
      return if Bundler.settings[:silence_root_warning] || Bundler::WINDOWS || !Process.uid.zero?
      Bundler.ui.warn "Don't run Bundler as root. Bundler can ask for sudo " \
        "if it is needed, and installing your bundle as root will break this " \
        "application for all non-root users on this machine.", :wrap => true
    end

    def dependencies_count_for(definition)
      count = definition.dependencies.count
      "#{count} Gemfile #{count == 1 ? "dependency" : "dependencies"}"
    end

    def gems_installed_for(definition)
      count = definition.specs.count
      "#{count} #{count == 1 ? "gem" : "gems"} now installed"
    end

    def check_for_group_conflicts_in_cli_options
      conflicting_groups = Array(options[:without]) & Array(options[:with])
      return if conflicting_groups.empty?
      raise InvalidOption, "You can't list a group in both with and without." \
        " The offending groups are: #{conflicting_groups.join(", ")}."
    end

    def check_for_options_conflicts
      if (options[:path] || options[:deployment]) && options[:system]
        error_message = String.new
        error_message << "You have specified both --path as well as --system. Please choose only one option.\n" if options[:path]
        error_message << "You have specified both --deployment as well as --system. Please choose only one option.\n" if options[:deployment]
        raise InvalidOption.new(error_message)
      end
    end

    def check_trust_policy
      trust_policy = options["trust-policy"]
      unless Bundler.rubygems.security_policies.keys.unshift(nil).include?(trust_policy)
        raise InvalidOption, "RubyGems doesn't know about trust policy '#{trust_policy}'. " \
          "The known policies are: #{Bundler.rubygems.security_policies.keys.join(", ")}."
      end
      Bundler.settings.set_command_option_if_given :"trust-policy", trust_policy
    end

    def normalize_groups
      options[:with] &&= options[:with].join(":").tr(" ", ":").split(":")
      options[:without] &&= options[:without].join(":").tr(" ", ":").split(":")

      check_for_group_conflicts_in_cli_options

      Bundler.settings.set_command_option :with, nil if options[:with] == []
      Bundler.settings.set_command_option :without, nil if options[:without] == []

      with = options.fetch(:with, [])
      with |= Bundler.settings[:with].map(&:to_s)
      with -= options[:without] if options[:without]

      without = options.fetch(:without, [])
      without |= Bundler.settings[:without].map(&:to_s)
      without -= options[:with] if options[:with]

      options[:with]    = with
      options[:without] = without
    end

    def normalize_settings
      Bundler.settings.set_command_option :path, nil if options[:system]
      Bundler.settings.set_command_option :path, "vendor/bundle" if options[:deployment]
      Bundler.settings.set_command_option_if_given :path, options["path"]
      Bundler.settings.set_command_option :path, "bundle" if options["standalone"] && Bundler.settings[:path].nil?

      bin_option = options["binstubs"]
      bin_option = nil if bin_option && bin_option.empty?
      Bundler.settings.set_command_option :bin, bin_option if options["binstubs"]

      Bundler.settings.set_command_option_if_given :shebang, options["shebang"]

      Bundler.settings.set_command_option_if_given :jobs, options["jobs"]

      Bundler.settings.set_command_option_if_given :no_prune, options["no-prune"]

      Bundler.settings.set_command_option_if_given :no_install, options["no-install"]

      Bundler.settings.set_command_option_if_given :clean, options["clean"]

      unless Bundler.settings[:without] == options[:without] && Bundler.settings[:with] == options[:with]
        # need to nil them out first to get around validation for backwards compatibility
        Bundler.settings.set_command_option :without, nil
        Bundler.settings.set_command_option :with,    nil
        Bundler.settings.set_command_option :without, options[:without] - options[:with]
        Bundler.settings.set_command_option :with,    options[:with]
      end

      options[:force] = options[:redownload]
    end

    def warn_ambiguous_gems
      Installer.ambiguous_gems.to_a.each do |name, installed_from_uri, *also_found_in_uris|
        Bundler.ui.error "Warning: the gem '#{name}' was found in multiple sources."
        Bundler.ui.error "Installed from: #{installed_from_uri}"
        Bundler.ui.error "Also found in:"
        also_found_in_uris.each {|uri| Bundler.ui.error "  * #{uri}" }
        Bundler.ui.error "You should add a source requirement to restrict this gem to your preferred source."
        Bundler.ui.error "For example:"
        Bundler.ui.error "    gem '#{name}', :source => '#{installed_from_uri}'"
        Bundler.ui.error "Then uninstall the gem '#{name}' (or delete all bundled gems) and then install again."
      end
    end
  end
end
