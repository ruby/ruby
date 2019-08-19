# frozen_string_literal: true

$:.unshift File.expand_path("..", __FILE__)
$:.unshift File.expand_path("../../lib", __FILE__)

require "rubygems"
module Gem
  if defined?(@path_to_default_spec_map)
    @path_to_default_spec_map.delete_if do |_path, spec|
      spec.name == "bundler"
    end
  end
end

begin
  require File.expand_path("../support/path.rb", __FILE__)
  spec = Gem::Specification.load(Spec::Path.gemspec.to_s)
  rspec = spec.dependencies.find {|d| d.name == "rspec" }
  gem "rspec", rspec.requirement.to_s
  require "rspec"
  require "diff/lcs"
rescue LoadError
  abort "Run rake spec:deps to install development dependencies"
end

require "bundler/psyched_yaml"
require "bundler/vendored_fileutils"
require "uri"
require "digest"

# Delete the default copy of Bundler that RVM installs for us when running in CI
require "fileutils"
if ENV.select {|k, _v| k =~ /TRAVIS/ }.any? && Gem::Version.new(Gem::VERSION) > Gem::Version.new("2.0")
  Dir.glob(File.join(Gem::Specification.default_specifications_dir, "bundler*.gemspec")).each do |file|
    FileUtils.rm_rf(file)
  end

  Dir.glob(File.join(RbConfig::CONFIG["sitelibdir"], "bundler*")).each do |file|
    FileUtils.rm_rf(file)
  end
end

if File.expand_path(__FILE__) =~ %r{([^\w/\.-])}
  abort "The bundler specs cannot be run from a path that contains special characters (particularly #{$1.inspect})"
end

require "bundler"

Dir["#{File.expand_path("../support", __FILE__)}/*.rb"].each do |file|
  file = file.gsub(%r{\A#{Regexp.escape File.expand_path("..", __FILE__)}/}, "")
  require file unless file.end_with?("hax.rb")
end

$debug = false

Spec::Manpages.setup
Spec::Rubygems.setup
FileUtils.rm_rf(Spec::Path.gem_repo1)
ENV["RUBYOPT"] = "#{ENV["RUBYOPT"]} -r#{Spec::Path.spec_dir}/support/hax.rb"
ENV["BUNDLE_SPEC_RUN"] = "true"

# Don't wrap output in tests
ENV["THOR_COLUMNS"] = "10000"

Spec::CodeClimate.setup

module Gem
  def self.ruby=(ruby)
    @ruby = ruby
  end
end

RSpec.configure do |config|
  config.include Spec::Builders
  config.include Spec::Helpers
  config.include Spec::Indexes
  config.include Spec::Matchers
  config.include Spec::Path
  config.include Spec::Rubygems
  config.include Spec::Platforms
  config.include Spec::Sudo
  config.include Spec::Permissions

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.disable_monkey_patching!

  # Since failures cause us to keep a bunch of long strings in memory, stop
  # once we have a large number of failures (indicative of core pieces of
  # bundler being broken) so that running the full test suite doesn't take
  # forever due to memory constraints
  config.fail_fast ||= 25 if ENV["CI"]

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

  config.filter_run_excluding :ruby => LessThanProc.with(RUBY_VERSION)
  config.filter_run_excluding :rubygems => LessThanProc.with(Gem::VERSION)
  config.filter_run_excluding :git => LessThanProc.with(git_version)
  config.filter_run_excluding :rubygems_master => (ENV["RGV"] != "master")
  config.filter_run_excluding :bundler => LessThanProc.with(Bundler::VERSION.split(".")[0, 2].join("."))
  config.filter_run_excluding :ruby_repo => !(ENV["BUNDLE_RUBY"] && ENV["BUNDLE_GEM"]).nil?

  config.filter_run_when_matching :focus unless ENV["CI"]

  original_wd  = Dir.pwd
  original_env = ENV.to_hash.delete_if {|k, _v| k.start_with?(Bundler::EnvironmentPreserver::BUNDLER_PREFIX) }

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.around :each do |example|
    if ENV["BUNDLE_RUBY"]
      orig_ruby = Gem.ruby
      Gem.ruby = ENV["BUNDLE_RUBY"]
    end
    example.run
    Gem.ruby = orig_ruby if ENV["BUNDLE_RUBY"]
  end

  config.before :suite do
    if ENV["BUNDLE_RUBY"]
      FileUtils.cp_r Spec::Path.bindir, File.join(Spec::Path.root, "lib", "exe")
    end
  end

  config.before :all do
    build_repo1
  end

  config.before :each do
    reset!
    system_gems []
    in_app_root
    @command_executions = []
  end

  config.after :each do |example|
    all_output = @command_executions.map(&:to_s_verbose).join("\n\n")
    if example.exception && !all_output.empty?
      warn all_output unless config.formatters.grep(RSpec::Core::Formatters::DocumentationFormatter).empty?
      message = example.exception.message + "\n\nCommands:\n#{all_output}"
      (class << example.exception; self; end).send(:define_method, :message) do
        message
      end
    end

    Dir.chdir(original_wd)
    ENV.replace(original_env)
  end

  config.after :suite do
    if ENV["BUNDLE_RUBY"]
      FileUtils.rm_rf File.join(Spec::Path.root, "lib", "exe")
    end
  end
end
