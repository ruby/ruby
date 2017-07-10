# frozen_string_literal: true
require "spec_helper"

shared_examples "bundle install --standalone" do
  shared_examples "common functionality" do
    it "still makes the gems available to normal bundler" do
      args = expected_gems.map {|k, v| "#{k} #{v}" }
      expect(the_bundle).to include_gems(*args)
    end

    it "generates a bundle/bundler/setup.rb" do
      expect(bundled_app("bundle/bundler/setup.rb")).to exist
    end

    it "makes the gems available without bundler" do
      testrb = String.new <<-RUBY
        $:.unshift File.expand_path("bundle")
        require "bundler/setup"

      RUBY
      expected_gems.each do |k, _|
        testrb << "\nrequire \"#{k}\""
        testrb << "\nputs #{k.upcase}"
      end
      Dir.chdir(bundled_app) do
        ruby testrb, :no_lib => true
      end

      expect(out).to eq(expected_gems.values.join("\n"))
    end

    it "works on a different system" do
      FileUtils.mv(bundled_app, "#{bundled_app}2")

      testrb = String.new <<-RUBY
        $:.unshift File.expand_path("bundle")
        require "bundler/setup"

      RUBY
      expected_gems.each do |k, _|
        testrb << "\nrequire \"#{k}\""
        testrb << "\nputs #{k.upcase}"
      end
      Dir.chdir("#{bundled_app}2") do
        ruby testrb, :no_lib => true
      end

      expect(out).to eq(expected_gems.values.join("\n"))
    end
  end

  describe "with simple gems" do
    before do
      install_gemfile <<-G, :standalone => true
        source "file://#{gem_repo1}"
        gem "rails"
      G
    end

    let(:expected_gems) do
      {
        "actionpack" => "2.3.2",
        "rails" => "2.3.2",
      }
    end

    include_examples "common functionality"
  end

  describe "with gems with native extension" do
    before do
      install_gemfile <<-G, :standalone => true
        source "file://#{gem_repo1}"
        gem "very_simple_binary"
      G
    end

    it "generates a bundle/bundler/setup.rb with the proper paths", :rubygems => "2.4" do
      extension_line = File.read(bundled_app("bundle/bundler/setup.rb")).each_line.find {|line| line.include? "/extensions/" }.strip
      expect(extension_line).to start_with '$:.unshift "#{path}/../#{ruby_engine}/#{ruby_version}/extensions/'
      expect(extension_line).to end_with '/very_simple_binary-1.0"'
    end
  end

  describe "with gem that has an invalid gemspec" do
    before do
      build_git "bar", :gemspec => false do |s|
        s.write "lib/bar/version.rb", %(BAR_VERSION = '1.0')
        s.write "bar.gemspec", <<-G
          lib = File.expand_path('../lib/', __FILE__)
          $:.unshift lib unless $:.include?(lib)
          require 'bar/version'

          Gem::Specification.new do |s|
            s.name        = 'bar'
            s.version     = BAR_VERSION
            s.summary     = 'Bar'
            s.files       = Dir["lib/**/*.rb"]
            s.author      = 'Anonymous'
            s.require_path = [1,2]
          end
        G
      end
      install_gemfile <<-G, :standalone => true
        gem "bar", :git => "#{lib_path("bar-1.0")}"
      G
    end

    it "outputs a helpful error message" do
      expect(out).to include("You have one or more invalid gemspecs that need to be fixed.")
      expect(out).to include("bar 1.0 has an invalid gemspec")
    end
  end

  describe "with a combination of gems and git repos" do
    before do
      build_git "devise", "1.0"

      install_gemfile <<-G, :standalone => true
        source "file://#{gem_repo1}"
        gem "rails"
        gem "devise", :git => "#{lib_path("devise-1.0")}"
      G
    end

    let(:expected_gems) do
      {
        "actionpack" => "2.3.2",
        "devise" => "1.0",
        "rails" => "2.3.2",
      }
    end

    include_examples "common functionality"
  end

  describe "with groups" do
    before do
      build_git "devise", "1.0"

      install_gemfile <<-G, :standalone => true
        source "file://#{gem_repo1}"
        gem "rails"

        group :test do
          gem "rspec"
          gem "rack-test"
        end
      G
    end

    let(:expected_gems) do
      {
        "actionpack" => "2.3.2",
        "rails" => "2.3.2",
      }
    end

    include_examples "common functionality"

    it "allows creating a standalone file with limited groups" do
      bundle "install --standalone default"

      Dir.chdir(bundled_app) do
        load_error_ruby <<-RUBY, "spec", :no_lib => true
          $:.unshift File.expand_path("bundle")
          require "bundler/setup"

          require "actionpack"
          puts ACTIONPACK
          require "spec"
        RUBY
      end

      expect(out).to eq("2.3.2")
      expect(err).to eq("ZOMG LOAD ERROR")
    end

    it "allows --without to limit the groups used in a standalone" do
      bundle "install --standalone --without test"

      Dir.chdir(bundled_app) do
        load_error_ruby <<-RUBY, "spec", :no_lib => true
          $:.unshift File.expand_path("bundle")
          require "bundler/setup"

          require "actionpack"
          puts ACTIONPACK
          require "spec"
        RUBY
      end

      expect(out).to eq("2.3.2")
      expect(err).to eq("ZOMG LOAD ERROR")
    end

    it "allows --path to change the location of the standalone bundle" do
      bundle "install --standalone --path path/to/bundle"

      Dir.chdir(bundled_app) do
        ruby <<-RUBY, :no_lib => true
          $:.unshift File.expand_path("path/to/bundle")
          require "bundler/setup"

          require "actionpack"
          puts ACTIONPACK
        RUBY
      end

      expect(out).to eq("2.3.2")
    end

    it "allows remembered --without to limit the groups used in a standalone" do
      bundle "install --without test"
      bundle "install --standalone"

      Dir.chdir(bundled_app) do
        load_error_ruby <<-RUBY, "spec", :no_lib => true
          $:.unshift File.expand_path("bundle")
          require "bundler/setup"

          require "actionpack"
          puts ACTIONPACK
          require "spec"
        RUBY
      end

      expect(out).to eq("2.3.2")
      expect(err).to eq("ZOMG LOAD ERROR")
    end
  end

  describe "with gemcutter's dependency API" do
    let(:source_uri) { "http://localgemserver.test" }

    describe "simple gems" do
      before do
        gemfile <<-G
          source "#{source_uri}"
          gem "rails"
        G
        bundle "install --standalone", :artifice => "endpoint"
      end

      let(:expected_gems) do
        {
          "actionpack" => "2.3.2",
          "rails" => "2.3.2",
        }
      end

      include_examples "common functionality"
    end
  end

  describe "with --binstubs" do
    before do
      install_gemfile <<-G, :standalone => true, :binstubs => true
        source "file://#{gem_repo1}"
        gem "rails"
      G
    end

    let(:expected_gems) do
      {
        "actionpack" => "2.3.2",
        "rails" => "2.3.2",
      }
    end

    include_examples "common functionality"

    it "creates stubs that use the standalone load path" do
      Dir.chdir(bundled_app) do
        expect(`bin/rails -v`.chomp).to eql "2.3.2"
      end
    end

    it "creates stubs that can be executed from anywhere" do
      require "tmpdir"
      Dir.chdir(Dir.tmpdir) do
        sys_exec!(%(#{bundled_app("bin/rails")} -v))
        expect(out).to eq("2.3.2")
      end
    end

    it "creates stubs that can be symlinked" do
      pending "File.symlink is unsupported on Windows" if Bundler::WINDOWS

      symlink_dir = tmp("symlink")
      FileUtils.mkdir_p(symlink_dir)
      symlink = File.join(symlink_dir, "rails")

      File.symlink(bundled_app("bin/rails"), symlink)
      sys_exec!("#{symlink} -v")
      expect(out).to eq("2.3.2")
    end

    it "creates stubs with the correct load path" do
      extension_line = File.read(bundled_app("bin/rails")).each_line.find {|line| line.include? "$:.unshift" }.strip
      expect(extension_line).to eq "$:.unshift File.expand_path '../../bundle', path.realpath"
    end
  end
end

describe "bundle install --standalone" do
  include_examples("bundle install --standalone")
end

describe "bundle install --standalone run in a subdirectory" do
  before do
    subdir = bundled_app("bob")
    FileUtils.mkdir_p(subdir)
    Dir.chdir(subdir)
  end

  include_examples("bundle install --standalone")
end
