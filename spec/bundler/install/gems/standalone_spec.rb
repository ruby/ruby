# frozen_string_literal: true

RSpec.shared_examples "bundle install --standalone" do
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
      ruby testrb

      expect(out).to eq(expected_gems.values.join("\n"))
    end

    it "works on a different system" do
      begin
        FileUtils.mv(bundled_app, "#{bundled_app}2")
      rescue Errno::ENOTEMPTY
        puts "Couldn't rename test app since the target folder has these files: #{Dir.glob("#{bundled_app}2/*")}"
        raise
      end

      testrb = String.new <<-RUBY
        $:.unshift File.expand_path("bundle")
        require "bundler/setup"

      RUBY
      expected_gems.each do |k, _|
        testrb << "\nrequire \"#{k}\""
        testrb << "\nputs #{k.upcase}"
      end
      ruby testrb, :dir => "#{bundled_app}2"

      expect(out).to eq(expected_gems.values.join("\n"))
    end
  end

  describe "with simple gems" do
    before do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rails"
      G
      bundle "config --local path #{bundled_app("bundle")}"
      bundle :install, :standalone => true, :dir => cwd
    end

    let(:expected_gems) do
      {
        "actionpack" => "2.3.2",
        "rails" => "2.3.2",
      }
    end

    include_examples "common functionality"
  end

  describe "with gems with native extension", :ruby_repo do
    before do
      bundle "config --local path #{bundled_app("bundle")}"
      install_gemfile <<-G, :standalone => true, :dir => cwd
        source "#{file_uri_for(gem_repo1)}"
        gem "very_simple_binary"
      G
    end

    it "generates a bundle/bundler/setup.rb with the proper paths" do
      expected_path = bundled_app("bundle/bundler/setup.rb")
      extension_line = File.read(expected_path).each_line.find {|line| line.include? "/extensions/" }.strip
      expect(extension_line).to start_with '$:.unshift File.expand_path("#{path}/../#{ruby_engine}/#{ruby_version}/extensions/'
      expect(extension_line).to end_with '/very_simple_binary-1.0")'
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
      bundle "config --local path #{bundled_app("bundle")}"
      install_gemfile <<-G, :standalone => true, :dir => cwd, :raise_on_error => false
        gem "bar", :git => "#{lib_path("bar-1.0")}"
      G
    end

    it "outputs a helpful error message" do
      expect(err).to include("You have one or more invalid gemspecs that need to be fixed.")
      expect(err).to include("bar 1.0 has an invalid gemspec")
    end
  end

  describe "with a combination of gems and git repos" do
    before do
      build_git "devise", "1.0"

      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rails"
        gem "devise", :git => "#{lib_path("devise-1.0")}"
      G
      bundle "config --local path #{bundled_app("bundle")}"
      bundle :install, :standalone => true, :dir => cwd
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

      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rails"

        group :test do
          gem "rspec"
          gem "rack-test"
        end
      G
      bundle "config --local path #{bundled_app("bundle")}"
      bundle :install, :standalone => true, :dir => cwd
    end

    let(:expected_gems) do
      {
        "actionpack" => "2.3.2",
        "rails" => "2.3.2",
      }
    end

    include_examples "common functionality"

    it "allows creating a standalone file with limited groups" do
      bundle "config --local path #{bundled_app("bundle")}"
      bundle :install, :standalone => "default", :dir => cwd

      load_error_ruby <<-RUBY, "spec"
        $:.unshift File.expand_path("bundle")
        require "bundler/setup"

        require "actionpack"
        puts ACTIONPACK
        require "spec"
      RUBY

      expect(out).to eq("2.3.2")
      expect(err).to eq("ZOMG LOAD ERROR")
    end

    it "allows `without` configuration to limit the groups used in a standalone" do
      bundle "config --local path #{bundled_app("bundle")}"
      bundle "config --local without test"
      bundle :install, :standalone => true, :dir => cwd

      load_error_ruby <<-RUBY, "spec"
        $:.unshift File.expand_path("bundle")
        require "bundler/setup"

        require "actionpack"
        puts ACTIONPACK
        require "spec"
      RUBY

      expect(out).to eq("2.3.2")
      expect(err).to eq("ZOMG LOAD ERROR")
    end

    it "allows `path` configuration to change the location of the standalone bundle" do
      bundle "config --local path path/to/bundle"
      bundle "install", :standalone => true, :dir => cwd

      ruby <<-RUBY
        $:.unshift File.expand_path("path/to/bundle")
        require "bundler/setup"

        require "actionpack"
        puts ACTIONPACK
      RUBY

      expect(out).to eq("2.3.2")
    end

    it "allows `without` to limit the groups used in a standalone" do
      bundle "config --local without test"
      bundle :install, :dir => cwd
      bundle "config --local path #{bundled_app("bundle")}"
      bundle :install, :standalone => true, :dir => cwd

      load_error_ruby <<-RUBY, "spec"
        $:.unshift File.expand_path("bundle")
        require "bundler/setup"

        require "actionpack"
        puts ACTIONPACK
        require "spec"
      RUBY

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
        bundle "config --local path #{bundled_app("bundle")}"
        bundle :install, :standalone => true, :artifice => "endpoint", :dir => cwd
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

  describe "with --binstubs", :bundler => "< 3" do
    before do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rails"
      G
      bundle "config --local path #{bundled_app("bundle")}"
      bundle :install, :standalone => true, :binstubs => true, :dir => cwd
    end

    let(:expected_gems) do
      {
        "actionpack" => "2.3.2",
        "rails" => "2.3.2",
      }
    end

    include_examples "common functionality"

    it "creates stubs that use the standalone load path" do
      expect(sys_exec("bin/rails -v").chomp).to eql "2.3.2"
    end

    it "creates stubs that can be executed from anywhere" do
      require "tmpdir"
      sys_exec(%(#{bundled_app("bin/rails")} -v), :dir => Dir.tmpdir)
      expect(out).to eq("2.3.2")
    end

    it "creates stubs that can be symlinked" do
      skip "symlinks unsupported" if Gem.win_platform?

      symlink_dir = tmp("symlink")
      FileUtils.mkdir_p(symlink_dir)
      symlink = File.join(symlink_dir, "rails")

      File.symlink(bundled_app("bin/rails"), symlink)
      sys_exec("#{symlink} -v")
      expect(out).to eq("2.3.2")
    end

    it "creates stubs with the correct load path" do
      extension_line = File.read(bundled_app("bin/rails")).each_line.find {|line| line.include? "$:.unshift" }.strip
      expect(extension_line).to eq %($:.unshift File.expand_path "../../bundle", path.realpath)
    end
  end
end

RSpec.describe "bundle install --standalone" do
  let(:cwd) { bundled_app }

  include_examples("bundle install --standalone")
end

RSpec.describe "bundle install --standalone run in a subdirectory" do
  let(:cwd) { bundled_app("bob").tap(&:mkpath) }

  include_examples("bundle install --standalone")
end
