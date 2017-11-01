# frozen_string_literal: true

require "bundler/cli"

RSpec.describe "bundle executable" do
  it "returns non-zero exit status when passed unrecognized options" do
    bundle "--invalid_argument"
    expect(exitstatus).to_not be_zero if exitstatus
  end

  it "returns non-zero exit status when passed unrecognized task" do
    bundle "unrecognized-task"
    expect(exitstatus).to_not be_zero if exitstatus
  end

  it "looks for a binary and executes it if it's named bundler-<task>" do
    File.open(tmp("bundler-testtasks"), "w", 0o755) do |f|
      ruby = ENV['BUNDLE_RUBY'] || "/usr/bin/env ruby"
      f.puts "#!#{ruby}\nputs 'Hello, world'\n"
    end

    with_path_added(tmp) do
      bundle "testtasks"
    end

    expect(exitstatus).to be_zero if exitstatus
    expect(out).to eq("Hello, world")
  end

  context "with no arguments" do
    it "prints a concise help message", :bundler => "2" do
      bundle! ""
      expect(last_command.stderr).to be_empty
      expect(last_command.stdout).to include("Bundler version #{Bundler::VERSION}").
        and include("\n\nBundler commands:\n\n").
        and include("\n\n  Primary commands:\n").
        and include("\n\n  Utilities:\n").
        and include("\n\nOptions:\n")
    end
  end

  context "when ENV['BUNDLE_GEMFILE'] is set to an empty string" do
    it "ignores it" do
      gemfile bundled_app("Gemfile"), <<-G
        source "file://#{gem_repo1}"
        gem 'rack'
      G

      bundle :install, :env => { "BUNDLE_GEMFILE" => "" }

      expect(the_bundle).to include_gems "rack 1.0.0"
    end
  end

  context "when ENV['RUBYGEMS_GEMDEPS'] is set" do
    it "displays a warning" do
      gemfile bundled_app("Gemfile"), <<-G
        source "file://#{gem_repo1}"
        gem 'rack'
      G

      bundle :install, :env => { "RUBYGEMS_GEMDEPS" => "foo" }
      expect(out).to include("RUBYGEMS_GEMDEPS")
      expect(out).to include("conflict with Bundler")

      bundle :install, :env => { "RUBYGEMS_GEMDEPS" => "" }
      expect(out).not_to include("RUBYGEMS_GEMDEPS")
    end
  end

  context "with --verbose" do
    it "prints the running command" do
      gemfile ""
      bundle! "info bundler", :verbose => true
      expect(last_command.stdout).to start_with("Running `bundle info bundler --no-color --verbose` with bundler #{Bundler::VERSION}")
    end

    it "doesn't print defaults" do
      install_gemfile! "", :verbose => true
      expect(last_command.stdout).to start_with("Running `bundle install --no-color --retry 0 --verbose` with bundler #{Bundler::VERSION}")
    end

    it "doesn't print defaults" do
      install_gemfile! "", :verbose => true
      expect(last_command.stdout).to start_with("Running `bundle install --no-color --retry 0 --verbose` with bundler #{Bundler::VERSION}")
    end
  end

  describe "printing the outdated warning" do
    shared_examples_for "no warning" do
      it "prints no warning" do
        bundle "fail"
        expect(last_command.stdboth).to eq("Could not find command \"fail\".")
      end
    end

    let(:bundler_version) { "1.1" }
    let(:latest_version) { nil }
    before do
      bundle! "config --global disable_version_check false"

      simulate_bundler_version(bundler_version)
      if latest_version
        info_path = home(".bundle/cache/compact_index/rubygems.org.443.29b0360b937aa4d161703e6160654e47/info/bundler")
        info_path.parent.mkpath
        info_path.open("w") {|f| f.write "#{latest_version}\n" }
      end
    end

    context "when there is no latest version" do
      include_examples "no warning"
    end

    context "when the latest version is equal to the current version" do
      let(:latest_version) { bundler_version }
      include_examples "no warning"
    end

    context "when the latest version is less than the current version" do
      let(:latest_version) { "0.9" }
      include_examples "no warning"
    end

    context "when the latest version is greater than the current version" do
      let(:latest_version) { "222.0" }
      it "prints the version warning" do
        bundle "fail"
        expect(last_command.stdout).to start_with(<<-EOS.strip)
The latest bundler is #{latest_version}, but you are currently running #{bundler_version}.
To install the latest version, run `gem install bundler`
        EOS
      end

      context "and disable_version_check is set" do
        before { bundle! "config disable_version_check true" }
        include_examples "no warning"
      end

      context "running a parseable command" do
        it "prints no warning" do
          bundle! "config --parseable foo"
          expect(last_command.stdboth).to eq ""

          bundle "platform --ruby"
          expect(last_command.stdboth).to eq "Could not locate Gemfile"
        end
      end

      context "and is a pre-release" do
        let(:latest_version) { "222.0.0.pre.4" }
        it "prints the version warning" do
          bundle "fail"
          expect(last_command.stdout).to start_with(<<-EOS.strip)
The latest bundler is #{latest_version}, but you are currently running #{bundler_version}.
To install the latest version, run `gem install bundler --pre`
          EOS
        end
      end
    end
  end
end

RSpec.describe "bundler executable" do
  it "shows the bundler version just as the `bundle` executable does", :bundler => "< 2" do
    bundler "--version"
    expect(out).to eq("Bundler version #{Bundler::VERSION}")
  end

  it "shows the bundler version just as the `bundle` executable does", :bundler => "2" do
    bundler "--version"
    expect(out).to eq(Bundler::VERSION)
  end
end
