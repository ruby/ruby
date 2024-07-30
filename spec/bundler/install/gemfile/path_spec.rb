# frozen_string_literal: true

RSpec.describe "bundle install with explicit source paths" do
  it "fetches gems with a global path source", bundler: "< 3" do
    build_lib "foo"

    install_gemfile <<-G
      path "#{lib_path("foo-1.0")}"
      gem 'foo'
    G

    expect(the_bundle).to include_gems("foo 1.0")
  end

  it "fetches gems" do
    build_lib "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      path "#{lib_path("foo-1.0")}" do
        gem 'foo'
      end
    G

    expect(the_bundle).to include_gems("foo 1.0")
  end

  it "supports pinned paths" do
    build_lib "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem 'foo', :path => "#{lib_path("foo-1.0")}"
    G

    expect(the_bundle).to include_gems("foo 1.0")
  end

  it "supports relative paths" do
    build_lib "foo"

    relative_path = lib_path("foo-1.0").relative_path_from(bundled_app)

    install_gemfile <<-G
      source "https://gem.repo1"
      gem 'foo', :path => "#{relative_path}"
    G

    expect(the_bundle).to include_gems("foo 1.0")
  end

  it "expands paths" do
    build_lib "foo"

    relative_path = lib_path("foo-1.0").relative_path_from(Pathname.new("~").expand_path)

    install_gemfile <<-G
      source "https://gem.repo1"
      gem 'foo', :path => "~/#{relative_path}"
    G

    expect(the_bundle).to include_gems("foo 1.0")
  end

  it "expands paths raise error with not existing user's home dir" do
    skip "problems with ~ expansion" if Gem.win_platform?

    build_lib "foo"
    username = "some_unexisting_user"
    relative_path = lib_path("foo-1.0").relative_path_from(Pathname.new("/home/#{username}").expand_path)

    install_gemfile <<-G, raise_on_error: false
      source "https://gem.repo1"
      gem 'foo', :path => "~#{username}/#{relative_path}"
    G
    expect(err).to match("There was an error while trying to use the path `~#{username}/#{relative_path}`.")
    expect(err).to match("user #{username} doesn't exist")
  end

  it "expands paths relative to Bundler.root" do
    build_lib "foo", path: bundled_app("foo-1.0")

    install_gemfile <<-G
      source "https://gem.repo1"
      gem 'foo', :path => "./foo-1.0"
    G

    expect(the_bundle).to include_gems("foo 1.0", dir: bundled_app("subdir").mkpath)
  end

  it "sorts paths consistently on install and update when they start with ./" do
    build_lib "demo", path: lib_path("demo")
    build_lib "aaa", path: lib_path("demo/aaa")

    gemfile lib_path("demo/Gemfile"), <<-G
      source "https://gem.repo1"
      gemspec
      gem "aaa", :path => "./aaa"
    G

    checksums = checksums_section_when_enabled do |c|
      c.no_checksum "aaa", "1.0"
      c.no_checksum "demo", "1.0"
    end

    lockfile = <<~L
      PATH
        remote: .
        specs:
          demo (1.0)

      PATH
        remote: aaa
        specs:
          aaa (1.0)

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        aaa!
        demo!
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle :install, dir: lib_path("demo")
    expect(lib_path("demo/Gemfile.lock")).to read_as(lockfile)
    bundle :update, all: true, dir: lib_path("demo")
    expect(lib_path("demo/Gemfile.lock")).to read_as(lockfile)
  end

  it "expands paths when comparing locked paths to Gemfile paths" do
    build_lib "foo", path: bundled_app("foo-1.0")

    install_gemfile <<-G
      source "https://gem.repo1"
      gem 'foo', :path => File.expand_path("foo-1.0", __dir__)
    G

    bundle "config set --local frozen true"
    bundle :install
  end

  it "installs dependencies from the path even if a newer gem is available elsewhere" do
    system_gems "myrack-1.0.0"

    build_lib "myrack", "1.0", path: lib_path("nested/bar") do |s|
      s.write "lib/myrack.rb", "puts 'WIN OVERRIDE'"
    end

    build_lib "foo", path: lib_path("nested") do |s|
      s.add_dependency "myrack", "= 1.0"
    end

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => "#{lib_path("nested")}"
    G

    run "require 'myrack'"
    expect(out).to eq("WIN OVERRIDE")
  end

  it "works" do
    build_gem "foo", "1.0.0", to_system: true do |s|
      s.write "lib/foo.rb", "puts 'FAIL'"
    end

    build_lib "omg", "1.0", path: lib_path("omg") do |s|
      s.add_dependency "foo"
    end

    build_lib "foo", "1.0.0", path: lib_path("omg/foo")

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "omg", :path => "#{lib_path("omg")}"
    G

    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "works when using prereleases of 0.0.0" do
    build_lib "foo", "0.0.0.dev", path: lib_path("foo")

    gemfile <<~G
      source "https://gem.repo1"
      gem "foo", :path => "#{lib_path("foo")}"
    G

    lockfile <<~L
      PATH
        remote: #{lib_path("foo")}
        specs:
          foo (0.0.0.dev)

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      BUNDLED WITH
        #{Bundler::VERSION}
    L

    bundle :install

    expect(the_bundle).to include_gems "foo 0.0.0.dev"
  end

  it "works when using uppercase prereleases of 0.0.0" do
    build_lib "foo", "0.0.0.SNAPSHOT", path: lib_path("foo")

    gemfile <<~G
      source "https://gem.repo1"
      gem "foo", :path => "#{lib_path("foo")}"
    G

    lockfile <<~L
      PATH
        remote: #{lib_path("foo")}
        specs:
          foo (0.0.0.SNAPSHOT)

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      BUNDLED WITH
        #{Bundler::VERSION}
    L

    bundle :install

    expect(the_bundle).to include_gems "foo 0.0.0.SNAPSHOT"
  end

  it "handles downgrades" do
    build_lib "omg", "2.0", path: lib_path("omg")

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "omg", :path => "#{lib_path("omg")}"
    G

    build_lib "omg", "1.0", path: lib_path("omg")

    bundle :install

    expect(the_bundle).to include_gems "omg 1.0"
  end

  it "prefers gemspecs closer to the path root" do
    build_lib "premailer", "1.0.0", path: lib_path("premailer") do |s|
      s.write "gemfiles/ruby187.gemspec", <<-G
        Gem::Specification.new do |s|
          s.name    = 'premailer'
          s.version = '1.0.0'
          s.summary = 'Hi'
          s.authors = 'Me'
        end
      G
    end

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "premailer", :path => "#{lib_path("premailer")}"
    G

    # Installation of the 'gemfiles' gemspec would fail since it will be unable
    # to require 'premailer.rb'
    expect(the_bundle).to include_gems "premailer 1.0.0"
  end

  it "warns on invalid specs" do
    build_lib "foo"

    gemspec = lib_path("foo-1.0").join("foo.gemspec").to_s
    File.open(gemspec, "w") do |f|
      f.write <<-G
        Gem::Specification.new do |s|
          s.name = "foo"
        end
      G
    end

    install_gemfile <<-G, raise_on_error: false
      source "https://gem.repo1"
      gem "foo", :path => "#{lib_path("foo-1.0")}"
    G

    expect(err).to_not include("Your Gemfile has no gem server sources.")
    expect(err).to match(/is not valid. Please fix this gemspec./)
    expect(err).to match(/The validation error was 'missing value for attribute version'/)
    expect(err).to match(/You have one or more invalid gemspecs that need to be fixed/)
  end

  it "supports gemspec syntax" do
    build_lib "foo", "1.0", path: lib_path("foo") do |s|
      s.add_dependency "myrack", "1.0"
    end

    gemfile lib_path("foo/Gemfile"), <<-G
      source "https://gem.repo1"
      gemspec
    G

    bundle "install", dir: lib_path("foo")
    expect(the_bundle).to include_gems "foo 1.0", dir: lib_path("foo")
    expect(the_bundle).to include_gems "myrack 1.0", dir: lib_path("foo")
  end

  it "does not unlock dependencies of path sources" do
    build_repo4 do
      build_gem "graphql", "2.0.15"
      build_gem "graphql", "2.0.16"
    end

    build_lib "foo", "0.1.0", path: lib_path("foo") do |s|
      s.add_dependency "graphql", "~> 2.0"
    end

    gemfile_path = lib_path("foo/Gemfile")

    gemfile gemfile_path, <<-G
      source "https://gem.repo4"
      gemspec
    G

    lockfile_path = lib_path("foo/Gemfile.lock")

    checksums = checksums_section_when_enabled do |c|
      c.no_checksum "foo", "0.1.0"
      c.checksum gem_repo4, "graphql", "2.0.15"
    end

    original_lockfile = <<~L
      PATH
        remote: .
        specs:
          foo (0.1.0)
            graphql (~> 2.0)

      GEM
        remote: https://gem.repo4/
        specs:
          graphql (2.0.15)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    L

    lockfile lockfile_path, original_lockfile

    build_lib "foo", "0.1.1", path: lib_path("foo") do |s|
      s.add_dependency "graphql", "~> 2.0"
    end

    bundle "install", dir: lib_path("foo")
    expect(lockfile_path).to read_as(original_lockfile.gsub("foo (0.1.0)", "foo (0.1.1)"))
  end

  it "supports gemspec syntax with an alternative path" do
    build_lib "foo", "1.0", path: lib_path("foo") do |s|
      s.add_dependency "myrack", "1.0"
    end

    install_gemfile <<-G
      source "https://gem.repo1"
      gemspec :path => "#{lib_path("foo")}"
    G

    expect(the_bundle).to include_gems "foo 1.0"
    expect(the_bundle).to include_gems "myrack 1.0"
  end

  it "doesn't automatically unlock dependencies when using the gemspec syntax" do
    build_lib "foo", "1.0", path: lib_path("foo") do |s|
      s.add_dependency "myrack", ">= 1.0"
    end

    install_gemfile lib_path("foo/Gemfile"), <<-G, dir: lib_path("foo")
      source "https://gem.repo1"
      gemspec
    G

    build_gem "myrack", "1.0.1", to_system: true

    bundle "install", dir: lib_path("foo")

    expect(the_bundle).to include_gems "foo 1.0", dir: lib_path("foo")
    expect(the_bundle).to include_gems "myrack 1.0", dir: lib_path("foo")
  end

  it "doesn't automatically unlock dependencies when using the gemspec syntax and the gem has development dependencies" do
    build_lib "foo", "1.0", path: lib_path("foo") do |s|
      s.add_dependency "myrack", ">= 1.0"
      s.add_development_dependency "activesupport"
    end

    install_gemfile lib_path("foo/Gemfile"), <<-G, dir: lib_path("foo")
      source "https://gem.repo1"
      gemspec
    G

    build_gem "myrack", "1.0.1", to_system: true

    bundle "install", dir: lib_path("foo")

    expect(the_bundle).to include_gems "foo 1.0", dir: lib_path("foo")
    expect(the_bundle).to include_gems "myrack 1.0", dir: lib_path("foo")
  end

  it "raises if there are multiple gemspecs" do
    build_lib "foo", "1.0", path: lib_path("foo") do |s|
      s.write "bar.gemspec", build_spec("bar", "1.0").first.to_ruby
    end

    install_gemfile <<-G, raise_on_error: false
      source "https://gem.repo1"
      gemspec :path => "#{lib_path("foo")}"
    G

    expect(exitstatus).to eq(15)
    expect(err).to match(/There are multiple gemspecs/)
  end

  it "allows :name to be specified to resolve ambiguity" do
    build_lib "foo", "1.0", path: lib_path("foo") do |s|
      s.write "bar.gemspec"
    end

    install_gemfile <<-G
      source "https://gem.repo1"
      gemspec :path => "#{lib_path("foo")}", :name => "foo"
    G

    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "sets up executables" do
    build_lib "foo" do |s|
      s.executables = "foobar"
    end

    install_gemfile <<-G, verbose: true
      source "https://gem.repo1"
      path "#{lib_path("foo-1.0")}" do
        gem 'foo'
      end
    G
    expect(out).to include("Using foo 1.0 from source at `#{lib_path("foo-1.0")}` and installing its executables")
    expect(the_bundle).to include_gems "foo 1.0"

    bundle "exec foobar"
    expect(out).to eq("1.0")
  end

  it "handles directories in bin/" do
    build_lib "foo"
    lib_path("foo-1.0").join("foo.gemspec").rmtree
    lib_path("foo-1.0").join("bin/performance").mkpath

    install_gemfile <<-G
      source "https://gem.repo1"
      gem 'foo', '1.0', :path => "#{lib_path("foo-1.0")}"
    G
    expect(err).to be_empty
  end

  it "removes the .gem file after installing" do
    build_lib "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem 'foo', :path => "#{lib_path("foo-1.0")}"
    G

    expect(lib_path("foo-1.0").join("foo-1.0.gem")).not_to exist
  end

  describe "block syntax" do
    it "pulls all gems from a path block" do
      build_lib "omg"
      build_lib "hi2u"

      install_gemfile <<-G
        source "https://gem.repo1"
        path "#{lib_path}" do
          gem "omg"
          gem "hi2u"
        end
      G

      expect(the_bundle).to include_gems "omg 1.0", "hi2u 1.0"
    end
  end

  it "keeps source pinning" do
    build_lib "foo", "1.0", path: lib_path("foo")
    build_lib "omg", "1.0", path: lib_path("omg")
    build_lib "foo", "1.0", path: lib_path("omg/foo") do |s|
      s.write "lib/foo.rb", "puts 'FAIL'"
    end

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => "#{lib_path("foo")}"
      gem "omg", :path => "#{lib_path("omg")}"
    G

    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "works when the path does not have a gemspec" do
    build_lib "foo", gemspec: false

    gemfile <<-G
      source "https://gem.repo1"
      gem "foo", "1.0", :path => "#{lib_path("foo-1.0")}"
    G

    expect(the_bundle).to include_gems "foo 1.0"

    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "works when the path does not have a gemspec but there is a lockfile" do
    lockfile <<~L
      PATH
        remote: vendor/bar
        specs:

      GEM
        remote: http://rubygems.org/
    L

    FileUtils.mkdir_p(bundled_app("vendor/bar"))

    install_gemfile <<-G
      source "http://rubygems.org"
      gem "bar", "1.0.0", path: "vendor/bar", require: "bar/nyard"
    G
  end

  context "existing lockfile" do
    it "rubygems gems don't re-resolve without changes" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem 'myrack-obama', '1.0'
        gem 'net-ssh', '1.0'
      G

      bundle :check, env: { "DEBUG" => "1" }
      expect(out).to match(/using resolution from the lockfile/)
      expect(the_bundle).to include_gems "myrack-obama 1.0", "net-ssh 1.0"
    end

    it "source path gems w/deps don't re-resolve without changes" do
      build_lib "myrack-obama", "1.0", path: lib_path("omg") do |s|
        s.add_dependency "yard"
      end

      build_lib "net-ssh", "1.0", path: lib_path("omg") do |s|
        s.add_dependency "yard"
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem 'myrack-obama', :path => "#{lib_path("omg")}"
        gem 'net-ssh', :path => "#{lib_path("omg")}"
      G

      bundle :check, env: { "DEBUG" => "1" }
      expect(out).to match(/using resolution from the lockfile/)
      expect(the_bundle).to include_gems "myrack-obama 1.0", "net-ssh 1.0"
    end
  end

  it "installs executable stubs" do
    build_lib "foo" do |s|
      s.executables = ["foo"]
    end

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => "#{lib_path("foo-1.0")}"
    G

    bundle "exec foo"
    expect(out).to eq("1.0")
  end

  describe "when the gem version in the path is updated" do
    before :each do
      build_lib "foo", "1.0", path: lib_path("foo") do |s|
        s.add_dependency "bar"
      end
      build_lib "bar", "1.0", path: lib_path("foo/bar")

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :path => "#{lib_path("foo")}"
      G
    end

    it "unlocks all gems when the top level gem is updated" do
      build_lib "foo", "2.0", path: lib_path("foo") do |s|
        s.add_dependency "bar"
      end

      bundle "install"

      expect(the_bundle).to include_gems "foo 2.0", "bar 1.0"
    end

    it "unlocks all gems when a child dependency gem is updated" do
      build_lib "bar", "2.0", path: lib_path("foo/bar")

      bundle "install"

      expect(the_bundle).to include_gems "foo 1.0", "bar 2.0"
    end
  end

  describe "when dependencies in the path are updated" do
    before :each do
      build_lib "foo", "1.0", path: lib_path("foo")

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :path => "#{lib_path("foo")}"
      G
    end

    it "gets dependencies that are updated in the path" do
      build_lib "foo", "1.0", path: lib_path("foo") do |s|
        s.add_dependency "myrack"
      end

      bundle "install"

      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "keeps using the same version if it's compatible" do
      build_lib "foo", "1.0", path: lib_path("foo") do |s|
        s.add_dependency "myrack", "0.9.1"
      end

      bundle "install"

      expect(the_bundle).to include_gems "myrack 0.9.1"

      checksums = checksums_section_when_enabled do |c|
        c.no_checksum "foo", "1.0"
        c.checksum gem_repo1, "myrack", "0.9.1"
      end

      expect(lockfile).to eq <<~G
        PATH
          remote: #{lib_path("foo")}
          specs:
            foo (1.0)
              myrack (= 0.9.1)

        GEM
          remote: https://gem.repo1/
          specs:
            myrack (0.9.1)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          foo!
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      G

      build_lib "foo", "1.0", path: lib_path("foo") do |s|
        s.add_dependency "myrack"
      end

      bundle "install"

      expect(lockfile).to eq <<~G
        PATH
          remote: #{lib_path("foo")}
          specs:
            foo (1.0)
              myrack

        GEM
          remote: https://gem.repo1/
          specs:
            myrack (0.9.1)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          foo!
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      G

      expect(the_bundle).to include_gems "myrack 0.9.1"
    end

    it "keeps using the same version even when another dependency is added" do
      build_lib "foo", "1.0", path: lib_path("foo") do |s|
        s.add_dependency "myrack", "0.9.1"
      end

      bundle "install"

      expect(the_bundle).to include_gems "myrack 0.9.1"

      checksums = checksums_section_when_enabled do |c|
        c.no_checksum "foo", "1.0"
        c.checksum gem_repo1, "myrack", "0.9.1"
      end

      expect(lockfile).to eq <<~G
        PATH
          remote: #{lib_path("foo")}
          specs:
            foo (1.0)
              myrack (= 0.9.1)

        GEM
          remote: https://gem.repo1/
          specs:
            myrack (0.9.1)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          foo!
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      G

      build_lib "foo", "1.0", path: lib_path("foo") do |s|
        s.add_dependency "myrack"
        s.add_dependency "rake", rake_version
      end

      bundle "install"

      checksums.checksum gem_repo1, "rake", rake_version

      expect(lockfile).to eq <<~G
        PATH
          remote: #{lib_path("foo")}
          specs:
            foo (1.0)
              myrack
              rake (= #{rake_version})

        GEM
          remote: https://gem.repo1/
          specs:
            myrack (0.9.1)
            rake (#{rake_version})

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          foo!
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      G

      expect(the_bundle).to include_gems "myrack 0.9.1"
    end

    it "does not remove existing ruby platform" do
      build_lib "foo", "1.0", path: lib_path("foo") do |s|
        s.add_dependency "myrack", "0.9.1"
      end

      checksums = checksums_section_when_enabled do |c|
        c.no_checksum "foo", "1.0"
      end

      lockfile <<~L
        PATH
          remote: #{lib_path("foo")}
          specs:
            foo (1.0)

        PLATFORMS
          #{lockfile_platforms("ruby")}

        DEPENDENCIES
          foo!
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle "lock"

      checksums.checksum gem_repo1, "myrack", "0.9.1"

      expect(lockfile).to eq <<~G
        PATH
          remote: #{lib_path("foo")}
          specs:
            foo (1.0)
              myrack (= 0.9.1)

        GEM
          remote: https://gem.repo1/
          specs:
            myrack (0.9.1)

        PLATFORMS
          #{lockfile_platforms("ruby")}

        DEPENDENCIES
          foo!
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      G
    end
  end

  describe "switching sources" do
    it "doesn't switch pinned git sources to rubygems when pinning the parent gem to a path source" do
      build_gem "foo", "1.0", to_system: true do |s|
        s.write "lib/foo.rb", "raise 'fail'"
      end
      build_lib "foo", "1.0", path: lib_path("bar/foo")
      build_git "bar", "1.0", path: lib_path("bar") do |s|
        s.add_dependency "foo"
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "bar", :git => "#{lib_path("bar")}"
      G

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "bar", :path => "#{lib_path("bar")}"
      G

      expect(the_bundle).to include_gems "foo 1.0", "bar 1.0"
    end

    it "switches the source when the gem existed in rubygems and the path was already being used for another gem" do
      build_lib "foo", "1.0", path: lib_path("foo")
      build_gem "bar", "1.0", to_bundle: true do |s|
        s.write "lib/bar.rb", "raise 'fail'"
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "bar"
        path "#{lib_path("foo")}" do
          gem "foo"
        end
      G

      build_lib "bar", "1.0", path: lib_path("foo/bar")

      install_gemfile <<-G
        source "https://gem.repo1"
        path "#{lib_path("foo")}" do
          gem "foo"
          gem "bar"
        end
      G

      expect(the_bundle).to include_gems "bar 1.0"
    end
  end

  describe "when there are both a gemspec and remote gems" do
    it "doesn't query rubygems for local gemspec name" do
      build_lib "private_lib", "2.2", path: lib_path("private_lib")
      gemfile lib_path("private_lib/Gemfile"), <<-G
        source "http://localgemserver.test"
        gemspec
        gem 'myrack'
      G
      bundle :install, env: { "DEBUG" => "1" }, artifice: "endpoint", dir: lib_path("private_lib")
      expect(out).to match(%r{^HTTP GET http://localgemserver\.test/api/v1/dependencies\?gems=myrack$})
      expect(out).not_to match(/^HTTP GET.*private_lib/)
      expect(the_bundle).to include_gems "private_lib 2.2", dir: lib_path("private_lib")
      expect(the_bundle).to include_gems "myrack 1.0", dir: lib_path("private_lib")
    end
  end

  describe "gem install hooks" do
    it "runs pre-install hooks" do
      build_git "foo"
      gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      File.open(lib_path("install_hooks.rb"), "w") do |h|
        h.write <<-H
          Gem.pre_install_hooks << lambda do |inst|
            STDERR.puts "Ran pre-install hook: \#{inst.spec.full_name}"
          end
        H
      end

      bundle :install,
        requires: [lib_path("install_hooks.rb")]
      expect(err_without_deprecations).to eq("Ran pre-install hook: foo-1.0")
    end

    it "runs post-install hooks" do
      build_git "foo"
      gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      File.open(lib_path("install_hooks.rb"), "w") do |h|
        h.write <<-H
          Gem.post_install_hooks << lambda do |inst|
            STDERR.puts "Ran post-install hook: \#{inst.spec.full_name}"
          end
        H
      end

      bundle :install,
        requires: [lib_path("install_hooks.rb")]
      expect(err_without_deprecations).to eq("Ran post-install hook: foo-1.0")
    end

    it "complains if the install hook fails" do
      build_git "foo"
      gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      File.open(lib_path("install_hooks.rb"), "w") do |h|
        h.write <<-H
          Gem.pre_install_hooks << lambda do |inst|
            false
          end
        H
      end

      bundle :install, requires: [lib_path("install_hooks.rb")], raise_on_error: false
      expect(err).to include("failed for foo-1.0")
    end

    it "loads plugins from the path gem" do
      foo_file = home("foo_plugin_loaded")
      bar_file = home("bar_plugin_loaded")
      expect(foo_file).not_to be_file
      expect(bar_file).not_to be_file

      build_lib "foo" do |s|
        s.write("lib/rubygems_plugin.rb", "require 'fileutils'; FileUtils.touch('#{foo_file}')")
      end

      build_git "bar" do |s|
        s.write("lib/rubygems_plugin.rb", "require 'fileutils'; FileUtils.touch('#{bar_file}')")
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :path => "#{lib_path("foo-1.0")}"
        gem "bar", :path => "#{lib_path("bar-1.0")}"
      G

      expect(foo_file).to be_file
      expect(bar_file).to be_file
    end
  end
end
