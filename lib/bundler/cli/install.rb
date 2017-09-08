# frozen_string_literal: true
require "bundler/cli/common"

module Bundler
  class CLI::Install
    attr_reader :options
    def initialize(options)
      @options = options
    end

    def run
      Bundler.ui.level = "error" if options[:quiet]

      warn_if_root

      [:with, :without].each do |option|
        if options[option]
          options[option] = options[option].join(":").tr(" ", ":").split(":")
        end
      end

      check_for_group_conflicts

      normalize_groups

      ENV["RB_USER_INSTALL"] = "1" if Bundler::FREEBSD

      # Disable color in deployment mode
      Bundler.ui.shell = Thor::Shell::Basic.new if options[:deployment]

      check_for_options_conflicts

      check_trust_policy

      if options[:deployment] || options[:frozen]
        unless Bundler.default_lockfile.exist?
          flag = options[:deployment] ? "--deployment" : "--frozen"
          raise ProductionError, "The #{flag} flag requires a #{Bundler.default_lockfile.relative_path_from(SharedHelpers.pwd)}. Please make " \
                                 "sure you have checked your #{Bundler.default_lockfile.relative_path_from(SharedHelpers.pwd)} into version control " \
                                 "before deploying."
        end

        options[:local] = true if Bundler.app_cache.exist?

        Bundler.settings[:frozen] = "1"
      end

      # When install is called with --no-deployment, disable deployment mode
      if options[:deployment] == false
        Bundler.settings.delete(:frozen)
        options[:system] = true
      end

      normalize_settings

      Bundler::Fetcher.disable_endpoint = options["full-index"]

      if options["binstubs"]
        Bundler::SharedHelpers.major_deprecation \
          "The --binstubs option will be removed in favor of `bundle binstubs`"
      end

      Plugin.gemfile_install(Bundler.default_gemfile) if Bundler.feature_flag.plugins?

      definition = Bundler.definition
      definition.validate_runtime!

      installer = Installer.install(Bundler.root, definition, options)
      Bundler.load.cache if Bundler.app_cache.exist? && !options["no-cache"] && !Bundler.settings[:frozen]

      Bundler.ui.confirm "Bundle complete! #{dependencies_count_for(definition)}, #{gems_installed_for(definition)}."
      Bundler::CLI::Common.output_without_groups_message

      if Bundler.settings[:path]
        absolute_path = File.expand_path(Bundler.settings[:path])
        relative_path = absolute_path.sub(File.expand_path(".") + File::SEPARATOR, "." + File::SEPARATOR)
        Bundler.ui.confirm "Bundled gems are installed into #{relative_path}."
      else
        Bundler.ui.confirm "Use `bundle info [gemname]` to see where a bundled gem is installed."
      end

      Bundler::CLI::Common.output_post_install_messages installer.post_install_messages

      warn_ambiguous_gems

      if Bundler.settings[:clean] && Bundler.settings[:path]
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

    def check_for_group_conflicts
      if options[:without] && options[:with]
        conflicting_groups = options[:without] & options[:with]
        unless conflicting_groups.empty?
          Bundler.ui.error "You can't list a group in both, --with and --without." \
          " The offending groups are: #{conflicting_groups.join(", ")}."
          exit 1
        end
      end
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
      if options["trust-policy"]
        unless Bundler.rubygems.security_policies.keys.include?(options["trust-policy"])
          Bundler.ui.error "Rubygems doesn't know about trust policy '#{options["trust-policy"]}'. " \
            "The known policies are: #{Bundler.rubygems.security_policies.keys.join(", ")}."
          exit 1
        end
        Bundler.settings["trust-policy"] = options["trust-policy"]
      else
        Bundler.settings["trust-policy"] = nil if Bundler.settings["trust-policy"]
      end
    end

    def normalize_groups
      Bundler.settings.with    = [] if options[:with] && options[:with].empty?
      Bundler.settings.without = [] if options[:without] && options[:without].empty?

      with = options.fetch("with", [])
      with |= Bundler.settings.with.map(&:to_s)
      with -= options[:without] if options[:without]

      without = options.fetch("without", [])
      without |= Bundler.settings.without.map(&:to_s)
      without -= options[:with] if options[:with]

      options[:with]    = with
      options[:without] = without
    end

    def normalize_settings
      Bundler.settings[:path]                = nil if options[:system]
      Bundler.settings[:path]                = "vendor/bundle" if options[:deployment]
      Bundler.settings[:path]                = options["path"] if options["path"]
      Bundler.settings[:path]              ||= "bundle" if options["standalone"]

      Bundler.settings[:bin]                 = options["binstubs"] if options["binstubs"]
      Bundler.settings[:bin]                 = nil if options["binstubs"] && options["binstubs"].empty?

      Bundler.settings[:shebang]             = options["shebang"] if options["shebang"]

      Bundler.settings[:jobs]                = options["jobs"] if options["jobs"]

      Bundler.settings[:no_prune]            = true if options["no-prune"]

      Bundler.settings[:no_install]          = true if options["no-install"]

      Bundler.settings[:clean]               = options["clean"] if options["clean"]

      Bundler.settings.without               = options[:without]
      Bundler.settings.with                  = options[:with]

      Bundler.settings[:disable_shared_gems] = Bundler.settings[:path] ? true : nil
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
