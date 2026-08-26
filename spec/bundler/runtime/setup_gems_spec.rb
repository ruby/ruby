# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Bundler.setup" do
  it "should prepend gemspec require paths to $LOAD_PATH in order" do
    update_repo2 do
      build_gem("requirepaths") do |s|
        s.write("lib/rq.rb", "puts 'yay'")
        s.write("src/rq.rb", "puts 'nooo'")
        s.require_paths = %w[lib src]
      end
    end

    install_gemfile <<-G
      source "https://gem.repo2"
      gem "requirepaths", :require => nil
    G

    run "require 'rq'"
    expect(out).to eq("yay")
  end

  it "should clean $LOAD_PATH properly" do
    gem_name = "very_simple_binary"
    full_gem_name = gem_name + "-1.0"

    system_gems full_gem_name

    install_gemfile <<-G
      source "https://gem.repo1"
    G

    ruby <<-R
      require 'bundler'
      gem '#{gem_name}'

      puts $LOAD_PATH.count {|path| path =~ /#{gem_name}/} >= 2

      Bundler.setup

      puts $LOAD_PATH.count {|path| path =~ /#{gem_name}/} == 0
    R

    expect(out).to eq("true\ntrue")
  end

  context "with bundler is located in symlinked GEM_HOME" do
    let(:gem_home) { Dir.mktmpdir }
    let(:symlinked_gem_home) { tmp("gem_home-symlink").to_s }
    let(:full_name) { "bundler-#{Bundler::VERSION}" }

    before do
      File.symlink(gem_home, symlinked_gem_home)
      gems_dir = File.join(gem_home, "gems")
      specifications_dir = File.join(gem_home, "specifications")
      Dir.mkdir(gems_dir)
      Dir.mkdir(specifications_dir)

      File.symlink(source_root, File.join(gems_dir, full_name))

      gemspec_content = File.binread(gemspec).
                sub("Bundler::VERSION", %("#{Bundler::VERSION}")).
                lines.reject {|line| line.include?("lib/bundler/version") }.join

      File.open(File.join(specifications_dir, "#{full_name}.gemspec"), "wb") do |f|
        f.write(gemspec_content)
      end
    end

    it "should not remove itself from the LOAD_PATH and require a different copy of 'bundler/setup'" do
      install_gemfile "source 'https://gem.repo1'"

      ruby <<-R, env: { "GEM_PATH" => symlinked_gem_home }
        TracePoint.trace(:class) do |tp|
          if tp.path.include?("bundler") && !tp.path.start_with?("#{source_root}")
            puts "OMG. Defining a class from another bundler at \#{tp.path}:\#{tp.lineno}"
          end
        end
        gem 'bundler', '#{Bundler::VERSION}'
        require 'bundler/setup'
      R

      expect(out).to be_empty
    end
  end

  it "does not reveal system gems even when Gem.refresh is called" do
    system_gems "myrack-1.0.0"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "activesupport"
    G

    run <<-R
      puts Bundler.rubygems.installed_specs.map(&:name)
      Gem.refresh
      puts Bundler.rubygems.installed_specs.map(&:name)
    R

    expect(out).to include("activesupport")
    expect(out).not_to include("myrack")
  end

  describe "when a vendored gem specification uses the :path option" do
    let(:filesystem_root) do
      current = Pathname.new(Dir.pwd)
      current = current.parent until current == current.parent
      current
    end

    it "should resolve paths relative to the Gemfile" do
      path = bundled_app(File.join("vendor", "foo"))
      build_lib "foo", path: path

      # If the .gemspec exists, then Bundler handles the path differently.
      # See Source::Path.load_spec_files for details.
      FileUtils.rm(File.join(path, "foo.gemspec"))

      install_gemfile <<-G
        source "https://gem.repo1"
        gem 'foo', '1.2.3', :path => 'vendor/foo'
      G

      run <<-R, env: { "BUNDLE_GEMFILE" => bundled_app_gemfile.to_s }, dir: bundled_app.parent
        require 'foo'
      R
      expect(err).to be_empty
    end

    it "should make sure the Bundler.root is really included in the path relative to the Gemfile" do
      relative_path = File.join("vendor", Dir.pwd.gsub(/^#{filesystem_root}/, ""))
      absolute_path = bundled_app(relative_path)
      FileUtils.mkdir_p(absolute_path)
      build_lib "foo", path: absolute_path

      # If the .gemspec exists, then Bundler handles the path differently.
      # See Source::Path.load_spec_files for details.
      FileUtils.rm(File.join(absolute_path, "foo.gemspec"))

      gemfile <<-G
        source "https://gem.repo1"
        gem 'foo', '1.2.3', :path => '#{relative_path}'
      G

      bundle :install

      run <<-R, env: { "BUNDLE_GEMFILE" => bundled_app_gemfile.to_s }, dir: bundled_app.parent
        require 'foo'
      R

      expect(err).to be_empty
    end
  end

  describe "with git gems that don't have gemspecs" do
    before :each do
      build_git "no_gemspec", gemspec: false

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "no_gemspec", "1.0", :git => "#{lib_path("no_gemspec-1.0")}"
      G
    end

    it "loads the library via a virtual spec" do
      run <<-R
        require 'no_gemspec'
        puts NO_GEMSPEC
      R

      expect(out).to eq("1.0")
    end
  end

  describe "with bundled and system gems" do
    before :each do
      system_gems "myrack-1.0.0"

      install_gemfile <<-G
        source "https://gem.repo1"

        gem "activesupport", "2.3.5"
      G
    end

    it "does not pull in system gems" do
      run <<-R
        begin;
          require 'myrack'
        rescue LoadError
          puts 'WIN'
        end
      R

      expect(out).to eq("WIN")
    end

    it "provides a gem method" do
      run <<-R
        gem 'activesupport'
        require 'activesupport'
        puts ACTIVESUPPORT
      R

      expect(out).to eq("2.3.5")
    end

    it "raises an exception if gem is used to invoke a system gem not in the bundle" do
      run <<-R
        begin
          gem 'myrack'
        rescue LoadError => e
          puts e.message
        end
      R

      expect(out).to eq("myrack is not part of the bundle. Add it to your Gemfile.")
    end

    it "sets GEM_HOME appropriately" do
      run "puts ENV['GEM_HOME']"
      expect(out).to eq(default_bundle_path.to_s)
    end
  end

  describe "with system gems in the bundle" do
    before :each do
      bundle_config "path.system true"
      system_gems "myrack-1.0.0"

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", "1.0.0"
        gem "activesupport", "2.3.5"
      G
    end

    it "sets GEM_PATH appropriately" do
      run "puts Gem.path"
      paths = out.split("\n")
      expect(paths).to include(system_gem_path.to_s)
    end
  end

  describe "with a gemspec that requires other files" do
    before :each do
      build_git "bar", gemspec: false do |s|
        s.write "lib/bar/version.rb", %(BAR_VERSION = '1.0')
        s.write "bar.gemspec", <<-G
          require_relative 'lib/bar/version'

          Gem::Specification.new do |s|
            s.name        = 'bar'
            s.version     = BAR_VERSION
            s.summary     = 'Bar'
            s.files       = Dir["lib/**/*.rb"]
            s.author      = 'no one'
          end
        G
      end

      gemfile <<-G
        source "https://gem.repo1"
        gem "bar", :git => "#{lib_path("bar-1.0")}"
      G
    end

    it "evals each gemspec in the context of its parent directory" do
      bundle :install
      run "require 'bar'; puts BAR"
      expect(out).to eq("1.0")
    end

    it "error intelligently if the gemspec has a LoadError" do
      ref = update_git "bar", gemspec: false do |s|
        s.write "bar.gemspec", "require 'foobarbaz'"
      end.ref_for("HEAD")
      bundle :install, raise_on_error: false

      expect(err.lines.map(&:chomp)).to include(
        a_string_starting_with("[!] There was an error while loading `bar.gemspec`:"),
        " #  from #{default_bundle_path "bundler", "gems", "bar-1.0-#{ref[0, 12]}", "bar.gemspec"}:1",
        " >  require 'foobarbaz'"
      )
    end

    it "evals each gemspec with a binding from the top level" do
      bundle "install"

      ruby <<-RUBY
        require 'bundler'
        bundler_module = class << Bundler; self; end
        bundler_module.send(:remove_method, :require)
        def Bundler.require(path)
          raise StandardError, "didn't use binding from top level"
        end
        Bundler.load
      RUBY

      expect(err).to be_empty
      expect(out).to be_empty
    end
  end

  describe "when Bundler is bundled" do
    it "doesn't blow up" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "bundler", :path => "#{root}"
      G

      bundle %(exec ruby -e "require 'bundler'; Bundler.setup")
      expect(err).to be_empty
    end
  end

  describe "when BUNDLED WITH" do
    def lock_with(bundler_version = nil)
      lock = <<~L
        GEM
          remote: https://gem.repo1/
          specs:
            myrack (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          myrack
      L

      if bundler_version
        lock += "\nBUNDLED WITH\n   #{bundler_version}\n"
      end

      lock
    end

    before do
      bundle_config "path.system true"

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G
    end

    context "is not present" do
      it "does not change the lock" do
        lockfile lock_with(nil)
        ruby "require 'bundler/setup'"
        expect(lockfile).to eq lock_with(nil)
      end
    end

    context "is newer" do
      it "does not change the lock or warn" do
        lockfile lock_with(Bundler::VERSION.succ)
        ruby "require 'bundler/setup'"
        expect(out).to be_empty
        expect(err).to be_empty
        expect(lockfile).to eq lock_with(Bundler::VERSION.succ)
      end
    end

    context "is older" do
      it "does not change the lock" do
        system_gems "bundler-1.10.1"
        lockfile lock_with("1.10.1")
        ruby "require 'bundler/setup'"
        expect(lockfile).to eq lock_with("1.10.1")
      end
    end
  end

  describe "when RUBY VERSION" do
    let(:ruby_version) { nil }

    def lock_with(ruby_version = nil)
      checksums = checksums_section do |c|
        c.checksum gem_repo1, "myrack", "1.0.0"
      end

      lock = <<~L
        GEM
          remote: https://gem.repo1/
          specs:
            myrack (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          myrack
        #{checksums}
      L

      if ruby_version
        lock += "\nRUBY VERSION\n   ruby #{ruby_version}\n"
      end

      lock += <<~L

        BUNDLED WITH
          #{Bundler::VERSION}
      L

      lock
    end

    before do
      install_gemfile <<-G
        ruby ">= 0"
        source "https://gem.repo1"
        gem "myrack"
      G
      lockfile lock_with(ruby_version)
    end

    context "is not present" do
      # Skipped on ruby-core, and on the release-version CI variant, because
      # `ruby "require 'bundler/setup'"` does not activate bundler as a gem
      # there, so Source::Metadata falls back to a synthetic spec whose
      # cache_file does not exist on disk and LockfileGenerator#bundler_checksum
      # drops the bundler checksum, while the on-disk lockfile still has it.
      # In-development (.dev) versions never write a bundler checksum, so the
      # regular suite stays unaffected.
      it "does not change the lock", :ruby_repo do
        skip "bundler is loaded from the source tree, not installed as a gem" unless Bundler::VERSION.end_with?(".dev")

        expect { ruby "require 'bundler/setup'" }.not_to change { lockfile }
      end
    end

    context "is newer" do
      let(:ruby_version) { "5.5.5" }
      it "does not change the lock or warn" do
        expect { ruby "require 'bundler/setup'" }.not_to change { lockfile }
        expect(out).to be_empty
        expect(err).to be_empty
      end
    end

    context "is older" do
      let(:ruby_version) { "1.0.0" }
      it "does not change the lock" do
        expect { ruby "require 'bundler/setup'" }.not_to change { lockfile }
      end
    end
  end

  describe "with gemified standard libraries" do
    it "does not load Digest", :ruby_repo do
      build_git "bar", gemspec: false do |s|
        s.write "lib/bar/version.rb", %(BAR_VERSION = '1.0')
        s.write "bar.gemspec", <<-G
          require_relative 'lib/bar/version'

          Gem::Specification.new do |s|
            s.name        = 'bar'
            s.version     = BAR_VERSION
            s.summary     = 'Bar'
            s.files       = Dir["lib/**/*.rb"]
            s.author      = 'no one'

            s.add_dependency 'digest'
          end
        G
      end

      gemfile <<-G
        source "https://gem.repo1"
        gem "bar", :git => "#{lib_path("bar-1.0")}"
      G

      bundle :install, env: { "BUNDLE_LOCKFILE_CHECKSUMS" => "false" }

      ruby <<-RUBY, artifice: nil
        require 'bundler/setup'
        puts defined?(::Digest) ? "Digest defined" : "Digest undefined"
        require 'digest'
      RUBY
      expect(out).to eq("Digest undefined")
    end

    it "does not load Psych" do
      gemfile "source 'https://gem.repo1'"
      ruby <<-RUBY
        require 'bundler/setup'
        puts defined?(Psych::VERSION) ? Psych::VERSION : "undefined"
        require 'psych'
        puts Psych::VERSION
      RUBY
      pre_bundler, post_bundler = out.split("\n")
      expect(pre_bundler).to eq("undefined")
      expect(post_bundler).to match(/\d+\.\d+\.\d+/)
    end

    it "does not load openssl" do
      install_gemfile "source 'https://gem.repo1'"
      ruby <<-RUBY, artifice: nil
        require "bundler/setup"
        puts defined?(OpenSSL) || "undefined"
        require "openssl"
        puts defined?(OpenSSL) || "undefined"
      RUBY
      expect(out).to eq("undefined\nconstant")
    end

    it "does not load uri while reading gemspecs", rubygems: ">= 3.6.0.dev" do
      Dir.mkdir bundled_app("test")

      create_file(bundled_app("test/test.gemspec"), <<-G)
        Gem::Specification.new do |s|
          s.name = "test"
          s.version = "1.0.0"
          s.summary = "test"
          s.authors = ['John Doe']
          s.homepage = 'https://example.com'
        end
      G

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "test", path: "#{bundled_app("test")}"
      G

      ruby <<-RUBY, artifice: nil
        require "bundler/setup"
        puts defined?(URI) || "undefined"
        require "uri"
        puts defined?(URI) || "undefined"
      RUBY
      expect(out).to eq("undefined\nconstant")
    end

    it "activates default gems when they are part of the bundle, but not installed explicitly", :ruby_repo do
      default_delegate_version = ruby "gem 'delegate'; require 'delegate'; puts Delegator::VERSION"

      build_repo2 do
        build_gem "delegate", default_delegate_version
      end

      gemfile "source \"https://gem.repo2\"; gem 'delegate'"

      ruby <<-RUBY
        require "bundler/setup"
        require "delegate"
        puts defined?(::Delegator) ? "Delegator defined" : "Delegator undefined"
      RUBY

      expect(out).to eq("Delegator defined")
      expect(err).to be_empty
    end

    describe "default gem activation" do
      let(:exemptions) do
        exempts = %w[did_you_mean bundler uri pathname]
        exempts << "error_highlight" # added in Ruby 3.1 as a default gem
        exempts << "ruby2_keywords" # added in Ruby 3.1 as a default gem
        exempts << "syntax_suggest" # added in Ruby 3.2 as a default gem
        exempts
      end

      let(:activation_warning_hack) { <<~RUBY }
        require #{spec_dir.join("support/hax").to_s.dump}

        Gem::Specification.send(:alias_method, :bundler_spec_activate, :activate)
        Gem::Specification.send(:define_method, :activate) do
          unless #{exemptions.inspect}.include?(name)
            warn '-' * 80
            warn "activating \#{full_name}"
            warn(*caller)
            warn '*' * 80
          end
          bundler_spec_activate
        end
      RUBY

      let(:activation_warning_hack_rubyopt) do
        create_file("activation_warning_hack.rb", activation_warning_hack)
        "-r#{bundled_app("activation_warning_hack.rb")} #{ENV["RUBYOPT"]}"
      end

      let(:code) { <<~RUBY }
        require "pp"
        loaded_specs = Gem.loaded_specs.dup
        #{exemptions.inspect}.each {|s| loaded_specs.delete(s) }
        pp loaded_specs

        # not a default gem, but harmful to have loaded
        open_uri = $LOADED_FEATURES.grep(/open.uri/)
        unless open_uri.empty?
          warn "open_uri: \#{open_uri}"
        end
      RUBY

      it "activates no gems with -rbundler/setup" do
        install_gemfile "source 'https://gem.repo1'"
        ruby code, env: { "RUBYOPT" => activation_warning_hack_rubyopt + " -rbundler/setup" }, artifice: nil
        expect(out).to eq("{}")
      end

      it "activates no gems with bundle exec" do
        install_gemfile "source 'https://gem.repo1'"
        create_file("script.rb", code)
        bundle "exec ruby ./script.rb", env: { "RUBYOPT" => activation_warning_hack_rubyopt }
        expect(out).to eq("{}")
      end

      it "activates no gems with bundle exec that is loaded" do
        skip "not executable" if Gem.win_platform?

        install_gemfile "source 'https://gem.repo1'"
        create_file("script.rb", "#!/usr/bin/env ruby\n\n#{code}")
        FileUtils.chmod(0o777, bundled_app("script.rb"))
        bundle "exec ./script.rb", env: { "RUBYOPT" => activation_warning_hack_rubyopt }
        expect(out).to eq("{}")
      end

      it "does not load net-http-pipeline too early" do
        build_repo4 do
          build_gem "net-http-pipeline", "1.0.1"
        end

        system_gems "net-http-pipeline-1.0.1", gem_repo: gem_repo4

        gemfile <<-G
          source "https://gem.repo4"
          gem "net-http-pipeline", "1.0.1"
        G

        bundle_config "path vendor/bundle"

        bundle :install

        bundle :check

        expect(out).to eq("The Gemfile's dependencies are satisfied")
      end

      Gem::Specification.select(&:default_gem?).map(&:name).each do |g|
        it "activates newer versions of #{g}", :ruby_repo do
          skip if exemptions.include?(g)

          build_repo4 do
            build_gem g, "999999"
          end

          install_gemfile <<-G
            source "https://gem.repo4"
            gem "#{g}", "999999"
          G

          expect(the_bundle).to include_gem("#{g} 999999", env: { "RUBYOPT" => activation_warning_hack_rubyopt }, artifice: nil)
        end

        it "activates older versions of #{g}", :ruby_repo do
          skip if exemptions.include?(g)

          build_repo4 do
            build_gem g, "0.0.0.a"
          end

          install_gemfile <<-G
            source "https://gem.repo4"
            gem "#{g}", "0.0.0.a"
          G

          expect(the_bundle).to include_gem("#{g} 0.0.0.a", env: { "RUBYOPT" => activation_warning_hack_rubyopt }, artifice: nil)
        end
      end
    end
  end

  describe "after setup" do
    it "keeps Kernel#gem private" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      ruby <<-RUBY, raise_on_error: false
        require "bundler/setup"
        Object.new.gem "myrack"
        puts "FAIL"
      RUBY

      expect(stdboth).not_to include "FAIL"
      expect(err).to match(/private method [`']gem'/)
    end

    it "keeps Kernel#require private" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      ruby <<-RUBY, raise_on_error: false
        require "bundler/setup"
        Object.new.require "myrack"
        puts "FAIL"
      RUBY

      expect(stdboth).not_to include "FAIL"
      expect(err).to match(/private method [`']require'/)
    end

    it "memoizes initial set of specs when requiring bundler/setup, so that even if further code mutates dependencies, Bundler.definition.specs is not affected" do
      install_gemfile <<~G
        source "https://gem.repo1"
        gem "yard"
        gem "myrack", :group => :test
      G

      ruby <<-RUBY, raise_on_error: false
        require "bundler/setup"
        Bundler.require(:test).select! {|d| (d.groups & [:test]).any? }
        puts Bundler.definition.specs.map(&:name).join(", ")
      RUBY

      expect(out).to include("myrack, yard")
    end

    it "does not cause double loads when higher versions of default gems are activated before bundler" do
      build_repo2 do
        build_gem "json", "999.999.999" do |s|
          s.write "lib/json.rb", <<~RUBY
            module JSON
              VERSION = "999.999.999"
            end
          RUBY
        end
      end

      system_gems "json-999.999.999", gem_repo: gem_repo2

      install_gemfile "source 'https://gem.repo1'"
      ruby <<-RUBY
        require "json"
        require "bundler/setup"
        require "json"
      RUBY

      expect(err).to be_empty
    end
  end

  it "does not undo the Kernel.require decorations", rubygems: ">= 3.4.6" do
    install_gemfile "source 'https://gem.repo1'"
    script = bundled_app("bin/script")
    create_file(script, <<~RUBY)
      module Kernel
        module_function

        alias_method :require_before_extra_monkeypatches, :require

        def require(path)
          puts "requiring \#{path} used the monkeypatch"

          require_before_extra_monkeypatches(path)
        end
      end

      require "bundler/setup"

      require "foo"
    RUBY

    sys_exec "#{Gem.ruby} #{script}", raise_on_error: false
    expect(out).to include("requiring foo used the monkeypatch")
  end

  it "performs an automatic bundle install" do
    build_repo4 do
      build_gem "myrack", "1.0.0"
    end

    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack", :group => :test
    G

    bundle_config "auto_install 1"

    ruby <<-RUBY, artifice: "compact_index"
      require 'bundler/setup'
    RUBY
    expect(err).to be_empty
    expect(out).to include("Installing myrack 1.0.0")
  end

  context "in a read-only filesystem" do
    before do
      gemfile <<-G
        source "https://gem.repo4"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo4/

        PLATFORMS
          x86_64-darwin-19

        DEPENDENCIES

        BUNDLED WITH
          #{Bundler::VERSION}
      L
    end

    it "should fail loudly if the lockfile platforms don't include the current platform" do
      simulate_platform "x86_64-linux" do
        ruby <<-RUBY, raise_on_error: false, env: { "BUNDLER_SPEC_READ_ONLY" => "true", "BUNDLER_FORCE_TTY" => "true" }
          require "bundler/setup"
        RUBY
      end

      expect(err).to include("Your lockfile is missing the current platform, but can't be updated because file system is read-only")
    end
  end
end
