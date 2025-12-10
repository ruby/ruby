# frozen_string_literal: true

module Bundler
  class CLI::Install
    attr_reader :options
    def initialize(options)
      @options = options
    end

    def run
      Bundler.ui.level = "warn" if options[:quiet]

      warn_if_root

      if options[:local]
        Bundler.self_manager.restart_with_locked_bundler_if_needed
      else
        Bundler.self_manager.install_locked_bundler_and_restart_with_it_if_needed
      end

      Bundler::SharedHelpers.set_env "RB_USER_INSTALL", "1" if Gem.freebsd_platform?

      if target_rbconfig_path = options[:"target-rbconfig"]
        Bundler.rubygems.set_target_rbconfig(target_rbconfig_path)
      end

      check_trust_policy

      if Bundler.frozen_bundle? && !Bundler.default_lockfile.exist?
        flag = "deployment setting" if Bundler.settings[:deployment]
        flag = "frozen setting" if Bundler.settings[:frozen]
        raise ProductionError, "The #{flag} requires a lockfile. Please make " \
                               "sure you have checked your #{SharedHelpers.relative_lockfile_path} into version control " \
                               "before deploying."
      end

      normalize_settings

      Bundler::Fetcher.disable_endpoint = options["full-index"]

      Plugin.gemfile_install(Bundler.default_gemfile) if Bundler.settings[:plugins]

      # For install we want to enable strict validation
      # (rather than some optimizations we perform at app runtime).
      definition = Bundler.definition(strict: true)
      definition.validate_runtime!
      definition.lockfile = options["lockfile"] if options["lockfile"]
      definition.lockfile = false if options["no-lock"]

      installer = Installer.install(Bundler.root, definition, options)

      Bundler.settings.temporary(cache_all_platforms: options[:local] ? false : Bundler.settings[:cache_all_platforms]) do
        Bundler.load.cache(nil, options[:local]) if Bundler.app_cache.exist? && !options["no-cache"] && !Bundler.frozen_bundle?
      end

      Bundler.ui.confirm "Bundle complete! #{dependencies_count_for(definition)}, #{gems_installed_for(definition)}."
      Bundler::CLI::Common.output_without_groups_message(:install)

      if Bundler.use_system_gems?
        Bundler.ui.confirm "Use `bundle info [gemname]` to see where a bundled gem is installed."
      else
        relative_path = Bundler.configured_bundle_path.base_path_relative_to_pwd
        Bundler.ui.confirm "Bundled gems are installed into `#{relative_path}`"
      end

      Bundler::CLI::Common.output_post_install_messages installer.post_install_messages

      if CLI::Common.clean_after_install?
        require_relative "clean"
        Bundler::CLI::Clean.new(options).run
      end

      Bundler::CLI::Common.output_fund_metadata_summary
    rescue Gem::InvalidSpecificationException
      Bundler.ui.warn "You have one or more invalid gemspecs that need to be fixed."
      raise
    end

    private

    def warn_if_root
      return if Bundler.settings[:silence_root_warning] || Gem.win_platform? || !Process.uid.zero?
      Bundler.ui.warn "Don't run Bundler as root. Installing your bundle as root " \
                      "will break this application for all non-root users on this machine.", wrap: true
    end

    def dependencies_count_for(definition)
      count = definition.dependencies.count
      "#{count} Gemfile #{count == 1 ? "dependency" : "dependencies"}"
    end

    def gems_installed_for(definition)
      count = definition.specs.count
      "#{count} #{count == 1 ? "gem" : "gems"} now installed"
    end

    def check_trust_policy
      trust_policy = options["trust-policy"]
      unless Bundler.rubygems.security_policies.keys.unshift(nil).include?(trust_policy)
        raise InvalidOption, "RubyGems doesn't know about trust policy '#{trust_policy}'. " \
          "The known policies are: #{Bundler.rubygems.security_policies.keys.join(", ")}."
      end
      Bundler.settings.set_command_option_if_given :"trust-policy", trust_policy
    end

    def normalize_settings
      if options["standalone"] && Bundler.settings[:path].nil? && !options["local"]
        Bundler.settings.set_command_option :path, "bundle"
      end

      Bundler.settings.set_command_option_if_given :shebang, options["shebang"]

      Bundler.settings.set_command_option_if_given :jobs, options["jobs"]

      Bundler.settings.set_command_option_if_given :no_prune, options["no-prune"]

      Bundler.settings.set_command_option_if_given :no_install, options["no-install"]

      Bundler.settings.set_command_option_if_given :clean, options["clean"]

      options[:force] = options[:redownload] if options[:redownload]
    end
  end
end
