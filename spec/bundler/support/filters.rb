# frozen_string_literal: true

class RequirementChecker < Proc
  def self.against(provided)
    new do |required|
      requirement = Gem::Requirement.new(required)

      !requirement.satisfied_by?(provided)
    end.tap do |checker|
      checker.provided = provided
    end
  end

  attr_accessor :provided

  def inspect
    "\"#{provided}\""
  end
end

RSpec.configure do |config|
  config.filter_run_excluding realworld: true

  config.filter_run_excluding rubygems: RequirementChecker.against(Gem.rubygems_version)
  config.filter_run_excluding ruby_repo: !ENV["GEM_COMMAND"].nil?
  config.filter_run_excluding no_color_tty: Gem.win_platform? || !ENV["GITHUB_ACTION"].nil?
  config.filter_run_excluding permissions: Gem.win_platform?
  config.filter_run_excluding readline: Gem.win_platform?
  config.filter_run_excluding jruby_only: RUBY_ENGINE != "jruby"
  config.filter_run_excluding truffleruby_only: RUBY_ENGINE != "truffleruby"
  config.filter_run_excluding man: Gem.win_platform?

  config.filter_run_when_matching :focus unless ENV["CI"]

  config.before(:each, :bundler) do |example|
    bundle "config simulate_version #{example.metadata[:bundler]}"
  end
end
