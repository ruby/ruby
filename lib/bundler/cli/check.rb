# frozen_string_literal: true

module Bundler
  class CLI::Check
    attr_reader :options

    def initialize(options)
      @options = options
    end

    def run
      Bundler.settings.set_command_option_if_given :path, options[:path]

      definition = Bundler.definition
      definition.ensure_equivalent_gemfile_and_lockfile
      definition.validate_runtime!

      begin
        definition.check!
        not_installed = definition.missing_specs
      rescue GemNotFound, GitError, SolveFailure
        Bundler.ui.error "Bundler can't satisfy your Gemfile's dependencies."
        Bundler.ui.warn "Install missing gems with `bundle install`."
        exit 1
      end

      if not_installed.any?
        Bundler.ui.error "The following gems are missing"
        not_installed.each {|s| Bundler.ui.error " * #{s.name} (#{s.version})" }
        Bundler.ui.warn "Install missing gems with `bundle install`"
        exit 1
      else
        definition.lock(true) unless options[:"dry-run"]
        Bundler.ui.info "The Gemfile's dependencies are satisfied"
      end
    end
  end
end
