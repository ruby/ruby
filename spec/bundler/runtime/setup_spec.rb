# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Bundler.setup" do
  describe "with no arguments" do
    it "makes all groups available" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :group => :test
      G

      ruby <<-RUBY
        require 'bundler'
        Bundler.setup

        require 'myrack'
        puts MYRACK
      RUBY
      expect(err).to be_empty
      expect(out).to eq("1.0.0")
    end
  end

  describe "when called with groups" do
    before(:each) do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "yard"
        gem "myrack", :group => :test
      G
    end

    it "doesn't make all groups available" do
      ruby <<-RUBY
        require 'bundler'
        Bundler.setup(:default)

        begin
          require 'myrack'
        rescue LoadError
          puts "WIN"
        end
      RUBY
      expect(err).to be_empty
      expect(out).to eq("WIN")
    end

    it "accepts string for group name" do
      ruby <<-RUBY
        require 'bundler'
        Bundler.setup(:default, 'test')

        require 'myrack'
        puts MYRACK
      RUBY
      expect(err).to be_empty
      expect(out).to eq("1.0.0")
    end

    it "leaves all groups available if they were already" do
      ruby <<-RUBY
        require 'bundler'
        Bundler.setup
        Bundler.setup(:default)

        require 'myrack'
        puts MYRACK
      RUBY
      expect(err).to be_empty
      expect(out).to eq("1.0.0")
    end

    it "leaves :default available if setup is called twice" do
      ruby <<-RUBY
        require 'bundler'
        Bundler.setup(:default)
        Bundler.setup(:default, :test)

        begin
          require 'yard'
          puts "WIN"
        rescue LoadError
          puts "FAIL"
        end
      RUBY
      expect(err).to be_empty
      expect(out).to match("WIN")
    end

    it "handles multiple non-additive invocations" do
      ruby <<-RUBY, raise_on_error: false
        require 'bundler'
        Bundler.setup(:default, :test)
        Bundler.setup(:default)
        require 'myrack'

        puts "FAIL"
      RUBY

      expect(err).to match("myrack")
      expect(err).to match("LoadError")
      expect(out).not_to match("FAIL")
    end
  end

  context "load order" do
    def clean_load_path(lp)
      without_bundler_load_path = ruby("puts $LOAD_PATH").split("\n")
      lp -= [*without_bundler_load_path, lib_dir.to_s]
      lp.map! {|p| p.sub(system_gem_path.to_s, "") }
    end

    it "puts loaded gems after -I and RUBYLIB", :ruby_repo do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      ENV["RUBYOPT"] = "#{ENV["RUBYOPT"]} -Idash_i_dir"
      ENV["RUBYLIB"] = "rubylib_dir"

      ruby <<-RUBY
        require 'bundler'
        Bundler.setup
        puts $LOAD_PATH
      RUBY

      load_path = out.split("\n")
      myrack_load_order = load_path.index {|path| path.include?("myrack") }

      expect(err).to be_empty
      expect(load_path).to include(a_string_ending_with("dash_i_dir"), "rubylib_dir")
      expect(myrack_load_order).to be > 0
    end

    it "orders the load path correctly when there are dependencies" do
      bundle_config "path.system true"

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rails"
      G

      ruby <<-RUBY
        require 'bundler'
        gem "bundler", "#{Bundler::VERSION}"
        Bundler.setup
        puts $LOAD_PATH
      RUBY

      load_path = clean_load_path(out.split("\n"))

      expect(load_path).to start_with(
        "/gems/rails-2.3.2/lib",
        "/gems/activeresource-2.3.2/lib",
        "/gems/activerecord-2.3.2/lib",
        "/gems/actionpack-2.3.2/lib",
        "/gems/actionmailer-2.3.2/lib",
        "/gems/activesupport-2.3.2/lib",
        "/gems/rake-#{rake_version}/lib"
      )
    end

    it "falls back to order the load path alphabetically for backwards compatibility" do
      bundle_config "path.system true"

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "weakling"
        gem "duradura"
        gem "terranova"
      G

      ruby <<-RUBY
        require 'bundler/setup'
        puts $LOAD_PATH
      RUBY

      load_path = clean_load_path(out.split("\n"))

      expect(load_path).to start_with(
        "/gems/weakling-0.0.3/lib",
        "/gems/terranova-8/lib",
        "/gems/duradura-7.0/lib"
      )
    end
  end

  it "raises if the Gemfile was not yet installed" do
    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G

    ruby <<-R
      require 'bundler'

      begin
        Bundler.setup
        puts "FAIL"
      rescue Bundler::GemNotFound
        puts "WIN"
      end
    R

    expect(out).to eq("WIN")
  end

  it "doesn't create a Gemfile.lock if the setup fails" do
    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G

    ruby <<-R, raise_on_error: false
      require 'bundler'

      Bundler.setup
    R

    expect(bundled_app_lock).not_to exist
  end

  it "doesn't change the Gemfile.lock if the setup fails" do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G

    lockfile = File.read(bundled_app_lock)

    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
      gem "nosuchgem", "10.0"
    G

    ruby <<-R, raise_on_error: false
      require 'bundler'

      Bundler.setup
    R

    expect(File.read(bundled_app_lock)).to eq(lockfile)
  end

  it "makes a Gemfile.lock if setup succeeds" do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G

    File.read(bundled_app_lock)

    FileUtils.rm(bundled_app_lock)

    run "1"
    expect(bundled_app_lock).to exist
  end

  describe "$BUNDLE_GEMFILE" do
    context "user provides an absolute path" do
      it "uses BUNDLE_GEMFILE to locate the gemfile if present" do
        gemfile <<-G
          source "https://gem.repo1"
          gem "myrack"
        G

        gemfile bundled_app("4realz"), <<-G
          source "https://gem.repo1"
          gem "activesupport", "2.3.5"
        G

        ENV["BUNDLE_GEMFILE"] = bundled_app("4realz").to_s
        bundle :install

        expect(the_bundle).to include_gems "activesupport 2.3.5"
      end
    end

    context "an absolute path is not provided" do
      it "uses BUNDLE_GEMFILE to locate the gemfile if present and doesn't fail in deployment mode" do
        gemfile <<-G
          source "https://gem.repo1"
        G

        bundle "install"
        bundle_config "deployment true"

        ENV["BUNDLE_GEMFILE"] = "Gemfile"
        ruby <<-R
          require 'bundler'

          begin
            Bundler.setup
            puts "WIN"
          rescue ArgumentError => e
            puts "FAIL"
          end
        R

        expect(out).to eq("WIN")
      end
    end

    context "user sets it via `config set --local gemfile`" do
      it "uses the value in the config" do
        gemfile <<-G
          source "https://gem.repo1"
          gem "myrack"
        G

        gemfile bundled_app("CustomGemfile"), <<-G
          source "https://gem.repo1"
          gem "activesupport", "2.3.5"
        G

        bundle_config "gemfile #{bundled_app("CustomGemfile")}"
        bundle "install"

        ruby <<-R
          require 'bundler'
          Bundler.setup
          require 'activesupport'
          puts ACTIVESUPPORT
        R

        expect(out).to eq("2.3.5")
      end
    end
  end

  it "prioritizes gems in BUNDLE_PATH over gems in GEM_HOME" do
    ENV["BUNDLE_PATH"] = bundled_app(".bundle").to_s
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "myrack", "1.0.0"
    G

    build_gem "myrack", "1.0", to_system: true do |s|
      s.write "lib/myrack.rb", "MYRACK = 'FAIL'"
    end

    expect(the_bundle).to include_gems "myrack 1.0.0"
  end

  describe "integrate with rubygems" do
    describe "by replacing #gem" do
      before :each do
        install_gemfile <<-G
          source "https://gem.repo1"
          gem "myrack", "0.9.1"
        G
      end

      it "replaces #gem but raises when the gem is missing" do
        run <<-R
          begin
            gem "activesupport"
            puts "FAIL"
          rescue LoadError
            puts "WIN"
          end
        R

        expect(out).to eq("WIN")
      end

      it "replaces #gem but raises when the version is wrong" do
        run <<-R
          begin
            gem "myrack", "1.0.0"
            puts "FAIL"
          rescue LoadError
            puts "WIN"
          end
        R

        expect(out).to eq("WIN")
      end
    end

    describe "by hiding system gems" do
      before :each do
        system_gems "activesupport-2.3.5"
        install_gemfile <<-G
          source "https://gem.repo1"
          gem "yard"
        G
      end

      it "removes system gems from Gem.source_index" do
        run "require 'yard'"
        expect(out).to include("bundler-#{Bundler::VERSION}").and include("yard-1.0")
        expect(out).not_to include("activesupport-2.3.5")
      end

      context "when the ruby stdlib is a substring of Gem.path" do
        it "does not reject the stdlib from $LOAD_PATH" do
          substring = "/" + $LOAD_PATH.find {|p| p.include?("vendor_ruby") }.split("/")[2]
          run "puts 'worked!'", env: { "GEM_PATH" => substring }
          expect(out).to eq("worked!")
        end
      end
    end
  end

  describe "with paths" do
    it "activates the gems in the path source" do
      system_gems "myrack-1.0.0"

      build_lib "myrack", "1.0.0" do |s|
        s.write "lib/myrack.rb", "puts 'WIN'"
      end

      gemfile <<-G
        source "https://gem.repo1"
        path "#{lib_path("myrack-1.0.0")}" do
          gem "myrack"
        end
      G

      run "require 'myrack'"
      expect(out).to eq("WIN")
    end
  end

  describe "with git" do
    before do
      build_git "myrack", "1.0.0"

      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-1.0.0")}"
      G
    end

    it "provides a useful exception when the git repo is not checked out yet" do
      run "1", raise_on_error: false
      expect(err).to match(/the git source #{lib_path("myrack-1.0.0")} is not yet checked out. Please run `bundle install`/i)
    end

    it "does not hit the git binary if the lockfile is available and up to date" do
      bundle "install"

      break_git!

      ruby <<-R
        require 'bundler'

        begin
          Bundler.setup
          puts "WIN"
        rescue Exception => e
          puts "FAIL"
        end
      R

      expect(out).to eq("WIN")
    end

    it "provides a good exception if the lockfile is unavailable" do
      bundle "install"

      FileUtils.rm(bundled_app_lock)

      break_git!

      ruby <<-R
        require "bundler"

        begin
          Bundler.setup
          puts "FAIL"
        rescue Bundler::GitError => e
          puts e.message
        end
      R

      run "puts 'FAIL'", raise_on_error: false

      expect(err).not_to include "This is not the git you are looking for"
    end

    it "works even when the cache directory has been deleted" do
      bundle :install
      FileUtils.rm_r default_cache_path
      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "does not randomly change the path when specifying --path and the bundle directory becomes read only" do
      bundle_config "path vendor/bundle"
      bundle :install

      with_read_only("#{bundled_app}/**/*") do
        expect(the_bundle).to include_gems "myrack 1.0.0"
      end
    end

    it "finds git gem when default bundle path becomes read only" do
      bundle_config "path .bundle"
      bundle "install"

      with_read_only("#{bundled_app(".bundle")}/**/*") do
        expect(the_bundle).to include_gems "myrack 1.0.0"
      end
    end
  end

  describe "when specifying local override" do
    it "explodes if given path does not exist on runtime" do
      build_git "myrack", "0.8"

      FileUtils.cp_r("#{lib_path("myrack-0.8")}/.", lib_path("local-myrack"))

      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}", :branch => "main"
      G

      bundle %(config set local.myrack #{lib_path("local-myrack")})
      bundle :install

      FileUtils.rm_r(lib_path("local-myrack"))
      run "require 'myrack'", raise_on_error: false
      expect(err).to match(/Cannot use local override for myrack-0.8 because #{Regexp.escape(lib_path("local-myrack").to_s)} does not exist/)
    end

    it "explodes if branch is not given on runtime" do
      build_git "myrack", "0.8"

      FileUtils.cp_r("#{lib_path("myrack-0.8")}/.", lib_path("local-myrack"))

      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}", :branch => "main"
      G

      bundle %(config set local.myrack #{lib_path("local-myrack")})
      bundle :install

      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}"
      G

      run "require 'myrack'", raise_on_error: false
      expect(err).to match(/because :branch is not specified in Gemfile/)
    end

    it "explodes on different branches on runtime" do
      build_git "myrack", "0.8"

      FileUtils.cp_r("#{lib_path("myrack-0.8")}/.", lib_path("local-myrack"))

      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}", :branch => "main"
      G

      bundle %(config set local.myrack #{lib_path("local-myrack")})
      bundle :install

      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}", :branch => "changed"
      G

      run "require 'myrack'", raise_on_error: false
      expect(err).to match(/is using branch main but Gemfile specifies changed/)
    end

    it "explodes on refs with different branches on runtime" do
      build_git "myrack", "0.8"

      FileUtils.cp_r("#{lib_path("myrack-0.8")}/.", lib_path("local-myrack"))

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}", :ref => "main", :branch => "main"
      G

      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}", :ref => "main", :branch => "nonexistent"
      G

      bundle %(config set local.myrack #{lib_path("local-myrack")})
      run "require 'myrack'", raise_on_error: false
      expect(err).to match(/is using branch main but Gemfile specifies nonexistent/)
    end
  end

  describe "when excluding groups" do
    it "doesn't change the resolve if --without is used" do
      bundle_config "without rails"
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "activesupport"

        group :rails do
          gem "rails", "2.3.2"
        end
      G

      system_gems "activesupport-2.3.5"

      expect(the_bundle).to include_gems "activesupport 2.3.2", groups: :default
    end

    it "remembers --without and does not bail on bare Bundler.setup" do
      bundle_config "without rails"
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "activesupport"

        group :rails do
          gem "rails", "2.3.2"
        end
      G

      system_gems "activesupport-2.3.5"

      expect(the_bundle).to include_gems "activesupport 2.3.2"
    end

    it "remembers --without and does not bail on bare Bundler.setup, even in the case of path gems no longer available" do
      bundle_config "without development"

      path = bundled_app(File.join("vendor", "foo"))
      build_lib "foo", path: path

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "activesupport", "2.3.2"
        gem 'foo', :path => 'vendor/foo', :group => :development
      G

      FileUtils.rm_r(path)

      ruby "require 'bundler'; Bundler.setup", env: { "DEBUG" => "1" }
      expect(out).to include("Assuming that source at `vendor/foo` has not changed since fetching its specs errored")
      expect(out).to include("Found no changes, using resolution from the lockfile")
      expect(err).to be_empty
    end

    it "doesn't re-resolve when a pre-release bundler is used and a dependency includes a dependency on bundler" do
      system_gems "bundler-9.99.9.beta1"

      build_repo4 do
        build_gem "depends_on_bundler", "1.0" do |s|
          s.add_dependency "bundler", ">= 1.5.0"
        end
      end

      install_gemfile <<~G
        source "https://gem.repo4"
        gem "depends_on_bundler"
      G

      ruby "require '#{system_gem_path("gems/bundler-9.99.9.beta1/lib/bundler.rb")}'; Bundler.setup", env: { "DEBUG" => "1" }
      expect(out).to include("Found no changes, using resolution from the lockfile")
      expect(out).not_to include("lockfile does not have all gems needed for the current platform")
      expect(err).to be_empty
    end

    it "doesn't fail in frozen mode when bundler is a Gemfile dependency" do
      install_gemfile <<~G
        source "https://gem.repo4"
        gem "bundler"
      G

      bundle "install --verbose", env: { "BUNDLE_FROZEN" => "true" }
      expect(err).to be_empty
    end

    it "doesn't re-resolve when deleting dependencies" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "actionpack"
      G

      install_gemfile <<-G, verbose: true
        source "https://gem.repo1"
        gem "myrack"
      G

      expect(out).to include("Some dependencies were deleted, using a subset of the resolution from the lockfile")
      expect(err).to be_empty
    end

    it "remembers --without and does not include groups passed to Bundler.setup" do
      bundle_config "without rails"
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "activesupport"

        group :myrack do
          gem "myrack"
        end

        group :rails do
          gem "rails", "2.3.2"
        end
      G

      expect(the_bundle).not_to include_gems "activesupport 2.3.2", groups: :myrack
      expect(the_bundle).to include_gems "myrack 1.0.0", groups: :myrack
    end
  end

  # RubyGems returns loaded_from as a string
  it "has loaded_from as a string on all specs" do
    build_git "foo"
    build_git "no-gemspec", gemspec: false

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
      gem "foo", :git => "#{lib_path("foo-1.0")}"
      gem "no-gemspec", "1.0", :git => "#{lib_path("no-gemspec-1.0")}"
    G

    run <<-R
      Gem.loaded_specs.each do |n, s|
        puts "FAIL" unless s.loaded_from.is_a?(String)
      end
    R

    expect(out).to be_empty
  end

  it "has gem_dir pointing to local repo" do
    build_lib "foo", "1.0", path: bundled_app

    install_gemfile <<-G
      source "https://gem.repo1"
      gemspec
    G

    run <<-R
      puts Gem.loaded_specs['foo'].gem_dir
    R

    expect(out).to eq(bundled_app.to_s)
  end

  it "does not load all gemspecs" do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G

    run <<-R
      File.open(File.join(Gem.dir, "specifications", "invalid.gemspec"), "w") do |f|
        f.write <<-RUBY
# -*- encoding: utf-8 -*-
# stub: invalid 1.0.0 ruby lib

Gem::Specification.new do |s|
  s.name = "invalid"
  s.version = "1.0.0"
  s.authors = ["Invalid Author"]
  s.files = ["lib/invalid.rb"]
  s.add_dependency "nonexistent-gem", "~> 999.999.999"
  s.validate!
end
        RUBY
      end
    R

    run <<-R
      File.open(File.join(Gem.dir, "specifications", "invalid-ext.gemspec"), "w") do |f|
        f.write <<-RUBY
# -*- encoding: utf-8 -*-
# stub: invalid-ext 1.0.0 ruby lib
# stub: a.ext\\0b.ext

Gem::Specification.new do |s|
  s.name = "invalid-ext"
  s.version = "1.0.0"
  s.authors = ["Invalid Author"]
  s.files = ["lib/invalid.rb"]
  s.required_ruby_version = "~> 0.8.0"
  s.validate!
end
        RUBY
      end
      # Need to write the gem.build_complete file,
      # otherwise the full spec is loaded to check the installed_by_version
      extensions_dir = Gem.default_ext_dir_for(Gem.dir) || File.join(Gem.dir, "extensions", Gem::Platform.local.to_s, Gem.extension_api_version)
      Bundler::FileUtils.mkdir_p(File.join(extensions_dir, "invalid-ext-1.0.0"))
      File.open(File.join(extensions_dir, "invalid-ext-1.0.0", "gem.build_complete"), "w") {}
    R

    run <<-R
      puts "Success"
    R

    expect(out).to eq("Success")
  end

  it "ignores empty gem paths" do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G

    ENV["GEM_HOME"] = ""
    bundle %(exec ruby -e "require 'set'")

    expect(err).to be_empty
  end

  it "can require rubygems without warnings, when using a local cache", :truffleruby do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G

    bundle "package"
    bundle %(exec ruby -w -e "require 'rubygems'")

    expect(err).to be_empty
  end

  context "when the user has `MANPATH` set", :man do
    before { ENV["MANPATH"] = "/foo#{File::PATH_SEPARATOR}" }

    it "adds the gem's man dir to the MANPATH" do
      build_repo4 do
        build_gem "with_man" do |s|
          s.write("man/man1/page.1", "MANPAGE")
        end
      end

      install_gemfile <<-G
        source "https://gem.repo4"
        gem "with_man"
      G

      run "puts ENV['MANPATH']"
      expect(out).to eq("#{default_bundle_path("gems/with_man-1.0/man")}#{File::PATH_SEPARATOR}/foo")
    end
  end

  context "when the user does not have `MANPATH` set", :man do
    before { ENV.delete("MANPATH") }

    it "adds the gem's man dir to the MANPATH, leaving : in the end so that system man pages still work" do
      build_repo4 do
        build_gem "with_man" do |s|
          s.write("man/man1/page.1", "MANPAGE")
        end

        build_gem "with_man_overriding_system_man" do |s|
          s.write("man/man1/ls.1", "LS MANPAGE")
        end
      end

      install_gemfile <<-G
        source "https://gem.repo4"
        gem "with_man"
      G

      run <<~RUBY
        puts ENV['MANPATH']
        require "open3"
        puts Open3.capture2e("man", "ls")[1].success?
      RUBY

      expect(out).to eq("#{default_bundle_path("gems/with_man-1.0/man")}#{File::PATH_SEPARATOR}\ntrue")

      install_gemfile <<-G
        source "https://gem.repo4"
        gem "with_man_overriding_system_man"
      G

      run <<~RUBY
        puts ENV['MANPATH']
        require "open3"
        puts Open3.capture2e({ "LC_ALL" => "C" }, "man", "ls")[0]
      RUBY

      lines = out.split("\n")

      expect(lines).to include("#{default_bundle_path("gems/with_man_overriding_system_man-1.0/man")}#{File::PATH_SEPARATOR}")
      expect(lines).to include("LS MANPAGE")
    end
  end
end
