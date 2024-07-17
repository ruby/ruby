# frozen_string_literal: true

RSpec.shared_examples "bundle install --standalone" do
  shared_examples "common functionality" do
    it "still makes the gems available to normal bundler" do
      args = expected_gems.map {|k, v| "#{k} #{v}" }
      expect(the_bundle).to include_gems(*args)
    end

    it "still makes system gems unavailable to normal bundler" do
      system_gems "myrack-1.0.0"

      expect(the_bundle).to_not include_gems("myrack")
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

    it "makes the gems available without bundler nor rubygems" do
      testrb = String.new <<-RUBY
        $:.unshift File.expand_path("bundle")
        require "bundler/setup"

      RUBY
      expected_gems.each do |k, _|
        testrb << "\nrequire \"#{k}\""
        testrb << "\nputs #{k.upcase}"
      end
      sys_exec %(#{Gem.ruby} --disable-gems -w -e #{testrb.shellescape})

      expect(out).to eq(expected_gems.values.join("\n"))
    end

    it "makes the gems available without bundler via Kernel.require" do
      testrb = String.new <<-RUBY
        $:.unshift File.expand_path("bundle")
        require "bundler/setup"

      RUBY
      expected_gems.each do |k, _|
        testrb << "\nKernel.require \"#{k}\""
        testrb << "\nputs #{k.upcase}"
      end
      ruby testrb

      expect(out).to eq(expected_gems.values.join("\n"))
    end

    it "makes system gems unavailable without bundler" do
      system_gems "myrack-1.0.0"

      testrb = String.new <<-RUBY
        $:.unshift File.expand_path("bundle")
        require "bundler/setup"

        begin
          require "myrack"
        rescue LoadError
          puts "LoadError"
        end
      RUBY
      ruby testrb

      expect(out).to eq("LoadError")
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
      ruby testrb, dir: "#{bundled_app}2"

      expect(out).to eq(expected_gems.values.join("\n"))
    end

    it "skips activating gems" do
      testrb = String.new <<-RUBY
        $:.unshift File.expand_path("bundle")
        require "bundler/setup"

        gem "do_not_activate_me"
      RUBY
      expected_gems.each do |k, _|
        testrb << "\nrequire \"#{k}\""
        testrb << "\nputs #{k.upcase}"
      end
      sys_exec %(#{Gem.ruby} -w -e #{testrb.shellescape})

      expect(out).to eq(expected_gems.values.join("\n"))
    end
  end

  describe "with simple gems" do
    before do
      gemfile <<-G
        source "https://gem.repo1"
        gem "rails"
      G
      bundle "config set --local path #{bundled_app("bundle")}"
      bundle :install, standalone: true, dir: cwd
    end

    let(:expected_gems) do
      {
        "actionpack" => "2.3.2",
        "rails" => "2.3.2",
      }
    end

    include_examples "common functionality"
  end

  describe "with default gems and a lockfile", :ruby_repo do
    before do
      skip "Does not work on old Windows Rubies" if Gem.ruby_version < Gem::Version.new("3.2") && Gem.win_platform?

      necessary_system_gems = ["tsort --version 0.1.0"]
      necessary_system_gems += ["etc --version 1.4.3"] if Gem.ruby_version >= Gem::Version.new("3.3.2") && Gem.win_platform?
      realworld_system_gems(*necessary_system_gems)

      necessary_gems_in_bundle_path = ["optparse --version 0.1.1", "psych --version 3.3.2", "logger --version 1.4.3", "etc --version 1.4.3", "stringio --version 3.1.0"]
      necessary_gems_in_bundle_path += ["shellwords --version 0.1.0", "base64 --version 0.1.0", "resolv --version 0.2.1"] if Gem.rubygems_version < Gem::Version.new("3.3.a")
      necessary_gems_in_bundle_path += ["yaml --version 0.1.1"] if Gem.rubygems_version < Gem::Version.new("3.4.a")
      realworld_system_gems(*necessary_gems_in_bundle_path, path: scoped_gem_path(bundled_app("bundle")))

      build_gem "foo", "1.0.0", to_system: true, default: true do |s|
        s.add_dependency "bar"
      end

      build_gem "bar", "1.0.0", to_system: true, default: true

      build_repo4 do
        build_gem "foo", "1.0.0" do |s|
          s.add_dependency "bar"
        end

        build_gem "bar", "1.0.0"
      end

      gemfile <<-G
        source "https://gem.repo4"
        gem "foo"
      G

      bundle "lock", dir: cwd, artifice: "compact_index"
    end

    it "works and points to the vendored copies, not to the default copies" do
      bundle "config set --local path #{bundled_app("bundle")}"
      bundle :install, standalone: true, dir: cwd, env: { "BUNDLER_GEM_DEFAULT_DIR" => system_gem_path.to_s }

      load_path_lines = bundled_app("bundle/bundler/setup.rb").read.split("\n").select {|line| line.start_with?("$:.unshift") }

      expect(load_path_lines).to eq [
        '$:.unshift File.expand_path("#{__dir__}/../#{RUBY_ENGINE}/#{Gem.ruby_api_version}/gems/bar-1.0.0/lib")',
        '$:.unshift File.expand_path("#{__dir__}/../#{RUBY_ENGINE}/#{Gem.ruby_api_version}/gems/foo-1.0.0/lib")',
      ]
    end
  end

  describe "with Gemfiles using absolute path sources and resulting bundle moved to a folder hierarchy with different nesting" do
    before do
      build_lib "minitest", "1.0.0", path: lib_path("minitest")

      Dir.mkdir bundled_app("app")

      gemfile bundled_app("app/Gemfile"), <<-G
        source "https://gem.repo1"
        gem "minitest", :path => "#{lib_path("minitest")}"
      G

      bundle "install", standalone: true, dir: bundled_app("app")

      Dir.mkdir tmp("one_more_level")
      FileUtils.mv bundled_app, tmp("one_more_level")
    end

    it "also works" do
      ruby <<-RUBY, dir: tmp("one_more_level/bundled_app/app")
        require "./bundle/bundler/setup"

        require "minitest"
        puts MINITEST
      RUBY

      expect(out).to eq("1.0.0")
      expect(err).to be_empty
    end
  end

  describe "with Gemfiles using relative path sources and app moved to a different root" do
    before do
      FileUtils.mkdir_p bundled_app("app/vendor")

      build_lib "minitest", "1.0.0", path: bundled_app("app/vendor/minitest")

      gemfile bundled_app("app/Gemfile"), <<-G
        source "https://gem.repo1"
        gem "minitest", :path => "vendor/minitest"
      G

      bundle "install", standalone: true, dir: bundled_app("app")

      FileUtils.mv(bundled_app("app"), bundled_app2("app"))
    end

    it "also works" do
      ruby <<-RUBY, dir: bundled_app2("app")
        require "./bundle/bundler/setup"

        require "minitest"
        puts MINITEST
      RUBY

      expect(out).to eq("1.0.0")
      expect(err).to be_empty
    end
  end

  describe "with gems with native extension" do
    before do
      bundle "config set --local path #{bundled_app("bundle")}"
      install_gemfile <<-G, standalone: true, dir: cwd
        source "https://gem.repo1"
        gem "very_simple_binary"
      G
    end

    it "generates a bundle/bundler/setup.rb with the proper paths" do
      expected_path = bundled_app("bundle/bundler/setup.rb")
      script_content = File.read(expected_path)
      expect(script_content).to include("def self.ruby_api_version")
      expect(script_content).to include("def self.extension_api_version")
      extension_line = script_content.each_line.find {|line| line.include? "/extensions/" }.strip
      platform = Gem::Platform.local
      expect(extension_line).to start_with '$:.unshift File.expand_path("#{__dir__}/../#{RUBY_ENGINE}/#{Gem.ruby_api_version}/extensions/'
      expect(extension_line).to end_with platform.to_s + '/#{Gem.extension_api_version}/very_simple_binary-1.0")'
    end
  end

  describe "with gem that has an invalid gemspec" do
    before do
      build_git "bar", gemspec: false do |s|
        s.write "lib/bar/version.rb", %(BAR_VERSION = '1.0')
        s.write "bar.gemspec", <<-G
          lib = File.expand_path('lib/', __dir__)
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
      bundle "config set --local path #{bundled_app("bundle")}"
      install_gemfile <<-G, standalone: true, dir: cwd, raise_on_error: false
        source "https://gem.repo1"
        gem "bar", :git => "#{lib_path("bar-1.0")}"
      G
    end

    it "outputs a helpful error message" do
      expect(err).to include("You have one or more invalid gemspecs that need to be fixed.")
      expect(err).to include("bar.gemspec is not valid")
    end
  end

  describe "with a combination of gems and git repos" do
    before do
      build_git "devise", "1.0"

      gemfile <<-G
        source "https://gem.repo1"
        gem "rails"
        gem "devise", :git => "#{lib_path("devise-1.0")}"
      G
      bundle "config set --local path #{bundled_app("bundle")}"
      bundle :install, standalone: true, dir: cwd
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
        source "https://gem.repo1"
        gem "rails"

        group :test do
          gem "rspec"
          gem "myrack-test"
        end
      G
      bundle "config set --local path #{bundled_app("bundle")}"
      bundle :install, standalone: true, dir: cwd
    end

    let(:expected_gems) do
      {
        "actionpack" => "2.3.2",
        "rails" => "2.3.2",
      }
    end

    include_examples "common functionality"

    it "allows creating a standalone file with limited groups" do
      bundle "config set --local path #{bundled_app("bundle")}"
      bundle :install, standalone: "default", dir: cwd

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
      bundle "config set --local path #{bundled_app("bundle")}"
      bundle "config set --local without test"
      bundle :install, standalone: true, dir: cwd

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
      bundle "config set --local path path/to/bundle"
      bundle "install", standalone: true, dir: cwd

      ruby <<-RUBY
        $:.unshift File.expand_path("path/to/bundle")
        require "bundler/setup"

        require "actionpack"
        puts ACTIONPACK
      RUBY

      expect(out).to eq("2.3.2")
    end

    it "allows `without` to limit the groups used in a standalone" do
      bundle "config set --local without test"
      bundle :install, dir: cwd
      bundle "config set --local path #{bundled_app("bundle")}"
      bundle :install, standalone: true, dir: cwd

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
        bundle "config set --local path #{bundled_app("bundle")}"
        bundle :install, standalone: true, artifice: "endpoint", dir: cwd
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

  describe "with --binstubs", bundler: "< 3" do
    before do
      gemfile <<-G
        source "https://gem.repo1"
        gem "rails"
      G
      bundle "config set --local path #{bundled_app("bundle")}"
      bundle :install, standalone: true, binstubs: true, dir: cwd
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
      sys_exec(%(#{bundled_app("bin/rails")} -v), dir: Dir.tmpdir)
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
      expect(extension_line).to eq %($:.unshift File.expand_path "../bundle", __dir__)
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

RSpec.describe "bundle install --standalone --local" do
  before do
    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G

    system_gems "myrack-1.0.0", path: default_bundle_path
  end

  it "generates script pointing to system gems" do
    bundle "install --standalone --local --verbose"

    expect(out).to include("Using myrack 1.0.0")

    load_error_ruby <<-RUBY, "spec"
      require "./bundler/setup"

      require "myrack"
      puts MYRACK
      require "spec"
    RUBY

    expect(out).to eq("1.0.0")
    expect(err).to eq("ZOMG LOAD ERROR")
  end
end
