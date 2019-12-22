# frozen_string_literal: true

require_relative "sudo"

class RequirementChecker < Proc
  def self.against(present)
    provided = Gem::Version.new(present)

    new do |required|
      !Gem::Requirement.new(required).satisfied_by?(provided)
    end.tap do |checker|
      checker.provided = provided
    end
  end

  attr_accessor :provided

  def inspect
    "\"!= #{provided}\""
  end
end

RSpec.configure do |config|
  if ENV["BUNDLER_SUDO_TESTS"] && Spec::Sudo.present?
    config.filter_run :sudo => true
  else
    config.filter_run_excluding :sudo => true
  end

  if ENV["BUNDLER_REALWORLD_TESTS"]
    config.filter_run :realworld => true
  else
    config.filter_run_excluding :realworld => true
  end

  git_version = Bundler::Source::Git::GitProxy.new(nil, nil, nil).version

  config.filter_run_excluding :rubygems => RequirementChecker.against(Gem::VERSION)
  config.filter_run_excluding :git => RequirementChecker.against(git_version)
  config.filter_run_excluding :bundler => RequirementChecker.against(Bundler::VERSION.split(".")[0])
  config.filter_run_excluding :ruby_repo => !ENV["GEM_COMMAND"].nil?
  config.filter_run_excluding :no_color_tty => Gem.win_platform? || !ENV["GITHUB_ACTION"].nil?

  config.filter_run_when_matching :focus unless ENV["CI"]
end
