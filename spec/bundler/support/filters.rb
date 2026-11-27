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

git_version = Gem::Version.new(`git --version`[/(\d+\.\d+\.\d+)/, 1])

RSpec.configure do |config|
  config.filter_run_excluding realworld: true

  # Version-gated specs care about the RubyGems that spec-spawned processes
  # run, which under RGV=system is older than the one loaded in this process.
  exercised_rubygems_version = Gem::Version.new(ENV["BUNDLER_SPEC_SYSTEM_RUBYGEMS_VERSION"] || Gem::VERSION)
  config.filter_run_excluding rubygems: RequirementChecker.against(exercised_rubygems_version)
  config.filter_run_excluding git: RequirementChecker.against(git_version)
  config.filter_run_excluding ruby_repo: !ENV["GEM_COMMAND"].nil?
  config.filter_run_excluding no_color_tty: Gem.win_platform? || !ENV["GITHUB_ACTION"].nil?
  config.filter_run_excluding permissions: Gem.win_platform?
  config.filter_run_excluding readline: Gem.win_platform?
  config.filter_run_excluding jruby_only: RUBY_ENGINE != "jruby"
  config.filter_run_excluding truffleruby_only: RUBY_ENGINE != "truffleruby"
  config.filter_run_excluding man: Gem.win_platform?
  config.filter_run_excluding mri_only: RUBY_ENGINE != "ruby"

  config.filter_run_when_matching :focus unless ENV["CI"]

  config.before(:each, :bundler) do |example|
    bundle_config "simulate_version #{example.metadata[:bundler]}"
  end
end
