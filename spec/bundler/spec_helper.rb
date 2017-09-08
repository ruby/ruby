# frozen_string_literal: true
$:.unshift File.expand_path("..", __FILE__)
$:.unshift File.expand_path("../../lib", __FILE__)

require "bundler/psyched_yaml"
require "fileutils"
require "uri"
require "digest/sha1"
require File.expand_path("../support/path.rb", __FILE__)

begin
  require "rubygems"
  spec = Gem::Specification.load(Spec::Path.gemspec.to_s)
  rspec = spec.dependencies.find {|d| d.name == "rspec" }
  gem "rspec", rspec.requirement.to_s
  require "rspec"
rescue LoadError
  abort "Run rake spec:deps to install development dependencies"
end

if File.expand_path(__FILE__) =~ %r{([^\w/\.])}
  abort "The bundler specs cannot be run from a path that contains special characters (particularly #{$1.inspect})"
end

require "bundler"

# Require the correct version of popen for the current platform
if RbConfig::CONFIG["host_os"] =~ /mingw|mswin/
  begin
    require "win32/open3"
  rescue LoadError
    abort "Run `gem install win32-open3` to be able to run specs"
  end
else
  require "open3"
end

Dir["#{File.expand_path("../support", __FILE__)}/*.rb"].each do |file|
  require file unless file.end_with?("hax.rb")
end

$debug = false

Spec::Rubygems.setup
FileUtils.rm_rf(Spec::Path.gem_repo1)
ENV["RUBYOPT"] = "#{ENV["RUBYOPT"]} -r#{Spec::Path.spec_dir}/support/hax.rb"
ENV["BUNDLE_SPEC_RUN"] = "true"
ENV["BUNDLE_PLUGINS"] = "true"

# Don't wrap output in tests
ENV["THOR_COLUMNS"] = "10000"

Spec::CodeClimate.setup

module Gem
  def self.ruby= ruby
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
  config.fail_fast ||= 25

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
  config.filter_run_excluding :ruby_repo => !!(ENV["BUNDLE_RUBY"] && ENV["BUNDLE_GEM"])

  config.filter_run_when_matching :focus unless ENV["CI"]

  original_wd  = Dir.pwd
  original_env = ENV.to_hash

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before :suite do
    @orig_ruby = if ENV['BUNDLE_RUBY']
                   ruby = Gem.ruby
                   Gem.ruby = ENV['BUNDLE_RUBY']
                   ruby
                 end
  end

  config.before :all do
    build_repo1
    # HACK: necessary until rspec-mocks > 3.5.0 is used
    # see https://github.com/bundler/bundler/pull/5363#issuecomment-278089256
    if RUBY_VERSION < "1.9"
      FileUtils.module_eval do
        alias_method :mkpath, :mkdir_p
        module_function :mkpath
      end
    end
  end

  config.before :each do
    reset!
    system_gems []
    in_app_root
    @all_output = String.new
  end

  config.after :each do |example|
    @all_output.strip!
    if example.exception && !@all_output.empty?
      warn @all_output unless config.formatters.grep(RSpec::Core::Formatters::DocumentationFormatter).empty?
      message = example.exception.message + "\n\nCommands:\n#{@all_output}"
      (class << example.exception; self; end).send(:define_method, :message) do
        message
      end
    end

    Dir.chdir(original_wd)
    ENV.replace(original_env)
  end

  config.after :suite do
    Gem.ruby = @orig_ruby
  end
end
