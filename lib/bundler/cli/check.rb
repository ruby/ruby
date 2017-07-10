# frozen_string_literal: true
module Bundler
  class CLI::Check
    attr_reader :options

    def initialize(options)
      @options = options
    end

    def run
      if options[:path]
        Bundler.settings[:path] = File.expand_path(options[:path])
        Bundler.settings[:disable_shared_gems] = true
      end

      begin
        definition = Bundler.definition
        definition.validate_runtime!
        not_installed = definition.missing_specs
      rescue GemNotFound, VersionConflict
        Bundler.ui.error "Bundler can't satisfy your Gemfile's dependencies."
        Bundler.ui.warn "Install missing gems with `bundle install`."
        exit 1
      end

      if not_installed.any?
        Bundler.ui.error "The following gems are missing"
        not_installed.each {|s| Bundler.ui.error " * #{s.name} (#{s.version})" }
        Bundler.ui.warn "Install missing gems with `bundle install`"
        exit 1
      elsif !Bundler.default_lockfile.file? && Bundler.settings[:frozen]
        Bundler.ui.error "This bundle has been frozen, but there is no #{Bundler.default_lockfile.relative_path_from(SharedHelpers.pwd)} present"
        exit 1
      else
        Bundler.load.lock(:preserve_unknown_sections => true) unless options[:"dry-run"]
        Bundler.ui.info "The Gemfile's dependencies are satisfied"
      end
    end
  end
end
