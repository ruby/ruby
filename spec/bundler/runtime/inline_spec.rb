# frozen_string_literal: true

RSpec.describe "bundler/inline#gemfile" do
  def script(code, options = {})
    requires = ["#{lib_dir}/bundler/inline"]
    requires.unshift "#{spec_dir}/support/artifice/" + options.delete(:artifice) if options.key?(:artifice)
    requires = requires.map {|r| "require '#{r}'" }.join("\n")
    ruby("#{requires}\n\n" + code, options)
  end

  before :each do
    build_lib "one", "1.0.0" do |s|
      s.write "lib/baz.rb", "puts 'baz'"
      s.write "lib/qux.rb", "puts 'qux'"
    end

    build_lib "two", "1.0.0" do |s|
      s.write "lib/two.rb", "puts 'two'"
      s.add_dependency "three", "= 1.0.0"
    end

    build_lib "three", "1.0.0" do |s|
      s.write "lib/three.rb", "puts 'three'"
      s.add_dependency "seven", "= 1.0.0"
    end

    build_lib "four", "1.0.0" do |s|
      s.write "lib/four.rb", "puts 'four'"
    end

    build_lib "five", "1.0.0", :no_default => true do |s|
      s.write "lib/mofive.rb", "puts 'five'"
    end

    build_lib "six", "1.0.0" do |s|
      s.write "lib/six.rb", "puts 'six'"
    end

    build_lib "seven", "1.0.0" do |s|
      s.write "lib/seven.rb", "puts 'seven'"
    end

    build_lib "eight", "1.0.0" do |s|
      s.write "lib/eight.rb", "puts 'eight'"
    end
  end

  it "requires the gems" do
    skip "gems not found" if Gem.win_platform?

    script <<-RUBY
      gemfile do
        path "#{lib_path}" do
          gem "two"
        end
      end
    RUBY

    expect(out).to eq("two")

    script <<-RUBY, :raise_on_error => false
      gemfile do
        path "#{lib_path}" do
          gem "eleven"
        end
      end

      puts "success"
    RUBY

    expect(err).to include "Could not find gem 'eleven'"
    expect(out).not_to include "success"

    script <<-RUBY
      gemfile(true) do
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      end
    RUBY

    expect(out).to include("Rack's post install message")

    script <<-RUBY, :artifice => "endpoint"
      gemfile(true) do
        source "https://notaserver.com"
        gem "activesupport", :require => true
      end
    RUBY

    expect(out).to include("Installing activesupport")
    err_lines = err.split("\n")
    err_lines.reject!{|line| line =~ /\.rb:\d+: warning: / } unless RUBY_VERSION < "2.7"
    expect(err_lines).to be_empty
  end

  it "lets me use my own ui object" do
    skip "prints just one CONFIRMED" if Gem.win_platform?

    script <<-RUBY, :artifice => "endpoint"
      require '#{lib_dir}/bundler'
      class MyBundlerUI < Bundler::UI::Silent
        def confirm(msg, newline = nil)
          puts "CONFIRMED!"
        end
      end
      gemfile(true, :ui => MyBundlerUI.new) do
        source "https://notaserver.com"
        gem "activesupport", :require => true
      end
    RUBY

    expect(out).to eq("CONFIRMED!\nCONFIRMED!")
  end

  it "has an option for quiet installation" do
    script <<-RUBY, :artifice => "endpoint"
      require '#{lib_dir}/bundler/inline'

      gemfile(true, :quiet => true) do
        source "https://notaserver.com"
        gem "activesupport", :require => true
      end
    RUBY

    expect(out).to be_empty
  end

  it "raises an exception if passed unknown arguments" do
    script <<-RUBY, :raise_on_error => false
      gemfile(true, :arglebargle => true) do
        path "#{lib_path}"
        gem "two"
      end

      puts "success"
    RUBY
    expect(err).to include "Unknown options: arglebargle"
    expect(out).not_to include "success"
  end

  it "does not mutate the option argument" do
    script <<-RUBY
      require '#{lib_dir}/bundler'
      options = { :ui => Bundler::UI::Shell.new }
      gemfile(false, options) do
        path "#{lib_path}" do
          gem "two"
        end
      end
      puts "OKAY" if options.key?(:ui)
    RUBY

    expect(out).to match("OKAY")
  end

  it "installs quietly if necessary when the install option is not set" do
    script <<-RUBY
      gemfile do
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      end

      puts RACK
    RUBY

    expect(out).to eq("1.0.0")
    expect(err).to be_empty
  end

  it "installs quietly from git if necessary when the install option is not set" do
    build_git "foo", "1.0.0"
    baz_ref = build_git("baz", "2.0.0").ref_for("HEAD")
    script <<-RUBY
      gemfile do
        gem "foo", :git => #{lib_path("foo-1.0.0").to_s.dump}
        gem "baz", :git => #{lib_path("baz-2.0.0").to_s.dump}, :ref => #{baz_ref.dump}
      end

      puts FOO
      puts BAZ
    RUBY

    expect(out).to eq("1.0.0\n2.0.0")
    expect(err).to be_empty
  end

  it "allows calling gemfile twice" do
    script <<-RUBY
      gemfile do
        path "#{lib_path}" do
          gem "two"
        end
      end

      gemfile do
        path "#{lib_path}" do
          gem "four"
        end
      end
    RUBY

    expect(out).to eq("two\nfour")
    expect(err).to be_empty
  end

  it "installs inline gems when a Gemfile.lock is present" do
    gemfile <<-G
      source "https://notaserver.com"
      gem "rake"
    G

    lockfile <<-G
      GEM
        remote: https://rubygems.org/
        specs:
          rake (11.3.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        rake

      BUNDLED WITH
         1.13.6
    G

    script <<-RUBY
      gemfile do
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      end

      puts RACK
    RUBY

    expect(err).to be_empty
  end

  it "installs inline gems when frozen is set" do
    script <<-RUBY, :env => { "BUNDLE_FROZEN" => "true" }
      gemfile do
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      end

      puts RACK
    RUBY

    expect(last_command.stderr).to be_empty
  end

  it "installs inline gems when BUNDLE_GEMFILE is set to an empty string" do
    ENV["BUNDLE_GEMFILE"] = ""

    script <<-RUBY
      gemfile do
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      end

      puts RACK
    RUBY

    expect(err).to be_empty
  end

  it "installs inline gems when BUNDLE_BIN is set" do
    ENV["BUNDLE_BIN"] = "/usr/local/bundle/bin"

    script <<-RUBY
      gemfile do
        source "#{file_uri_for(gem_repo1)}"
        gem "rack" # has the rackup executable
      end

      puts RACK
    RUBY
    expect(last_command).to be_success
    expect(out).to eq "1.0.0"
  end

  context "when BUNDLE_PATH is set" do
    it "installs inline gems to the system path regardless" do
      script <<-RUBY, :env => { "BUNDLE_PATH" => "./vendor/inline" }
        gemfile(true) do
          source "file://#{gem_repo1}"
          gem "rack"
        end
      RUBY
      expect(last_command).to be_success
      expect(system_gem_path("gems/rack-1.0.0")).to exist
    end
  end

  it "skips platform warnings" do
    simulate_platform "ruby"

    script <<-RUBY
      gemfile(true) do
        source "#{file_uri_for(gem_repo1)}"
        gem "rack", platform: :jruby
      end
    RUBY

    expect(err).to be_empty
  end

  it "preserves previous BUNDLE_GEMFILE value" do
    ENV["BUNDLE_GEMFILE"] = ""
    script <<-RUBY
      gemfile do
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      end

      puts "BUNDLE_GEMFILE is empty" if ENV["BUNDLE_GEMFILE"].empty?
      system("#{Gem.ruby} -w -e '42'") # this should see original value of BUNDLE_GEMFILE
      exit $?.exitstatus
    RUBY

    expect(last_command).to be_success
    expect(out).to include("BUNDLE_GEMFILE is empty")
  end

  it "resets BUNDLE_GEMFILE to the empty string if it wasn't set previously" do
    ENV["BUNDLE_GEMFILE"] = nil
    script <<-RUBY
      gemfile do
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      end

      puts "BUNDLE_GEMFILE is empty" if ENV["BUNDLE_GEMFILE"].empty?
      system("#{Gem.ruby} -w -e '42'") # this should see original value of BUNDLE_GEMFILE
      exit $?.exitstatus
    RUBY

    expect(last_command).to be_success
    expect(out).to include("BUNDLE_GEMFILE is empty")
  end

  it "does not error out if library requires optional dependencies" do
    Dir.mkdir tmp("path_without_gemfile")

    foo_code = <<~RUBY
      begin
        gem "bar"
      rescue LoadError
      end

      puts "WIN"
    RUBY

    build_lib "foo", "1.0.0" do |s|
      s.write "lib/foo.rb", foo_code
    end

    script <<-RUBY, :dir => tmp("path_without_gemfile")
      gemfile do
        path "#{lib_path}" do
          gem "foo", require: false
        end
      end

      require "foo"
    RUBY

    expect(out).to eq("WIN")
    expect(err).to be_empty
  end
end
