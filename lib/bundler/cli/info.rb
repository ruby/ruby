# frozen_string_literal: true
require "bundler/cli/common"

module Bundler
  class CLI::Info
    attr_reader :gem_name, :options
    def initialize(options, gem_name)
      @options = options
      @gem_name = gem_name
    end

    def run
      spec = spec_for_gem(gem_name)

      spec_not_found(gem_name) unless spec
      return print_gem_path(spec) if @options[:path]
      print_gem_info(spec)
    end

  private

    def spec_for_gem(gem_name)
      spec = Bundler.definition.specs.find {|s| s.name == gem_name }
      spec || default_gem_spec(gem_name)
    end

    def default_gem_spec(gem_name)
      return unless Gem::Specification.respond_to?(:find_all_by_name)
      gem_spec = Gem::Specification.find_all_by_name(gem_name).last
      return gem_spec if gem_spec && gem_spec.respond_to?(:default_gem?) && gem_spec.default_gem?
    end

    def spec_not_found(gem_name)
      raise GemNotFound, Bundler::CLI::Common.gem_not_found_message(gem_name, Bundler.definition.dependencies)
    end

    def print_gem_path(spec)
      Bundler.ui.info spec.full_gem_path
    end

    def print_gem_info(spec)
      gem_info = String.new
      gem_info << "  * #{spec.name} (#{spec.version}#{spec.git_version})\n"
      gem_info << "\tSummary: #{spec.summary}\n" if spec.summary
      gem_info << "\tHomepage: #{spec.homepage}\n" if spec.homepage
      gem_info << "\tPath: #{spec.full_gem_path}\n"
      gem_info << "\tDefault Gem: yes" if spec.respond_to?(:default_gem?) && spec.default_gem?
      Bundler.ui.info gem_info
    end
  end
end
