# frozen_string_literal: true

require_relative "support/path"

$:.unshift Spec::Path.spec_dir.to_s
$:.unshift Spec::Path.lib_dir.to_s

require "bundler/psyched_yaml"
require "bundler/vendored_fileutils"
require "bundler/vendored_uri"
require "digest"

if File.expand_path(__FILE__) =~ %r{([^\w/\.:\-])}
  abort "The bundler specs cannot be run from a path that contains special characters (particularly #{$1.inspect})"
end

require "bundler"
require "rspec"

require_relative "support/builders"
require_relative "support/filters"
require_relative "support/helpers"
require_relative "support/indexes"
require_relative "support/matchers"
require_relative "support/parallel"
require_relative "support/permissions"
require_relative "support/platforms"
require_relative "support/sometimes"
require_relative "support/sudo"

$debug = false

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

  config.bisect_runner = :shell

  original_wd  = Dir.pwd
  original_env = ENV.to_hash

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.allow_message_expectations_on_nil = false
  end

  config.around :each do |example|
    if ENV["RUBY"]
      orig_ruby = Gem.ruby
      Gem.ruby = ENV["RUBY"]
    end
    example.run
    Gem.ruby = orig_ruby if ENV["RUBY"]
  end

  config.before :suite do
    require_relative "support/rubygems_ext"
    Spec::Rubygems.setup
    ENV["RUBYOPT"] = "#{ENV["RUBYOPT"]} -r#{Spec::Path.spec_dir}/support/hax.rb"
    ENV["BUNDLE_SPEC_RUN"] = "true"
    ENV["BUNDLE_USER_CONFIG"] = ENV["BUNDLE_USER_CACHE"] = ENV["BUNDLE_USER_PLUGIN"] = nil
    ENV["GEMRC"] = nil

    # Don't wrap output in tests
    ENV["THOR_COLUMNS"] = "10000"

    original_env = ENV.to_hash

    if ENV["RUBY"]
      FileUtils.cp_r Spec::Path.bindir, File.join(Spec::Path.root, "lib", "exe")
    end
  end

  config.before :all do
    build_repo1
  end

  config.around :each do |example|
    ENV.replace(original_env)
    reset!
    system_gems []
    in_app_root
    @command_executions = []

    Bundler.ui.silence { example.run }

    all_output = @command_executions.map(&:to_s_verbose).join("\n\n")
    if example.exception && !all_output.empty?
      warn all_output unless config.formatters.grep(RSpec::Core::Formatters::DocumentationFormatter).empty?
      message = example.exception.message + "\n\nCommands:\n#{all_output}"
      (class << example.exception; self; end).send(:define_method, :message) do
        message
      end
    end

    Dir.chdir(original_wd)
  end

  config.after :suite do
    if ENV["RUBY"]
      FileUtils.rm_rf File.join(Spec::Path.root, "lib", "exe")
    end
  end
end
