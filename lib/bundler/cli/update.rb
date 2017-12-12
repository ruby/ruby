# frozen_string_literal: true

module Bundler
  class CLI::Update
    attr_reader :options, :gems
    def initialize(options, gems)
      @options = options
      @gems = gems
    end

    def run
      Bundler.ui.level = "error" if options[:quiet]

      Plugin.gemfile_install(Bundler.default_gemfile) if Bundler.feature_flag.plugins?

      sources = Array(options[:source])
      groups  = Array(options[:group]).map(&:to_sym)

      full_update = gems.empty? && sources.empty? && groups.empty? && !options[:ruby] && !options[:bundler]

      if full_update && !options[:all]
        if Bundler.feature_flag.update_requires_all_flag?
          raise InvalidOption, "To update everything, pass the `--all` flag."
        end
        SharedHelpers.major_deprecation 2, "Pass --all to `bundle update` to update everything"
      elsif !full_update && options[:all]
        raise InvalidOption, "Cannot specify --all along with specific options."
      end

      if full_update
        # We're doing a full update
        Bundler.definition(true)
      else
        unless Bundler.default_lockfile.exist?
          raise GemfileLockNotFound, "This Bundle hasn't been installed yet. " \
            "Run `bundle install` to update and install the bundled gems."
        end
        Bundler::CLI::Common.ensure_all_gems_in_lockfile!(gems)

        if groups.any?
          specs = Bundler.definition.specs_for groups
          gems.concat(specs.map(&:name))
        end

        Bundler.definition(:gems => gems, :sources => sources, :ruby => options[:ruby],
                           :lock_shared_dependencies => options[:conservative],
                           :bundler => options[:bundler])
      end

      Bundler::CLI::Common.configure_gem_version_promoter(Bundler.definition, options)

      Bundler::Fetcher.disable_endpoint = options["full-index"]

      opts = options.dup
      opts["update"] = true
      opts["local"] = options[:local]

      Bundler.settings.set_command_option_if_given :jobs, opts["jobs"]

      Bundler.definition.validate_runtime!
      installer = Installer.install Bundler.root, Bundler.definition, opts
      Bundler.load.cache if Bundler.app_cache.exist?

      if CLI::Common.clean_after_install?
        require "bundler/cli/clean"
        Bundler::CLI::Clean.new(options).run
      end

      if locked_gems = Bundler.definition.locked_gems
        gems.each do |name|
          locked_version = locked_gems.specs.find {|s| s.name == name }
          locked_version &&= locked_version.version
          next unless locked_version
          new_version = Bundler.definition.specs[name].first
          new_version &&= new_version.version
          if !new_version
            Bundler.ui.warn "Bundler attempted to update #{name} but it was removed from the bundle"
          elsif new_version < locked_version
            Bundler.ui.warn "Bundler attempted to update #{name} but its version regressed from #{locked_version} to #{new_version}"
          elsif new_version == locked_version
            Bundler.ui.warn "Bundler attempted to update #{name} but its version stayed the same"
          end
        end
      end

      Bundler.ui.confirm "Bundle updated!"
      Bundler::CLI::Common.output_without_groups_message
      Bundler::CLI::Common.output_post_install_messages installer.post_install_messages
    end
  end
end
