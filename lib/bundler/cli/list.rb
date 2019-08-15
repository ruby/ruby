# frozen_string_literal: true

module Bundler
  class CLI::List
    def initialize(options)
      @options = options
    end

    def run
      raise InvalidOption, "The `--only-group` and `--without-group` options cannot be used together" if @options["only-group"] && @options["without-group"]

      raise InvalidOption, "The `--name-only` and `--paths` options cannot be used together" if @options["name-only"] && @options[:paths]

      specs = if @options["only-group"] || @options["without-group"]
        filtered_specs_by_groups
      else
        Bundler.load.specs
      end.reject {|s| s.name == "bundler" }.sort_by(&:name)

      return Bundler.ui.info "No gems in the Gemfile" if specs.empty?

      return specs.each {|s| Bundler.ui.info s.name } if @options["name-only"]
      return specs.each {|s| Bundler.ui.info s.full_gem_path } if @options["paths"]

      Bundler.ui.info "Gems included by the bundle:"

      specs.each {|s| Bundler.ui.info "  * #{s.name} (#{s.version}#{s.git_version})" }

      Bundler.ui.info "Use `bundle info` to print more detailed information about a gem"
    end

  private

    def verify_group_exists(groups)
      raise InvalidOption, "`#{@options["without-group"]}` group could not be found." if @options["without-group"] && !groups.include?(@options["without-group"].to_sym)

      raise InvalidOption, "`#{@options["only-group"]}` group could not be found." if @options["only-group"] && !groups.include?(@options["only-group"].to_sym)
    end

    def filtered_specs_by_groups
      definition = Bundler.definition
      groups = definition.groups

      verify_group_exists(groups)

      show_groups =
        if @options["without-group"]
          groups.reject {|g| g == @options["without-group"].to_sym }
        elsif @options["only-group"]
          groups.select {|g| g == @options["only-group"].to_sym }
        else
          groups
        end.map(&:to_sym)

      definition.specs_for(show_groups)
    end
  end
end
