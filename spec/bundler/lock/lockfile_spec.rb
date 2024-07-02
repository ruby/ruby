# frozen_string_literal: true

RSpec.describe "the lockfile format" do
  before do
    build_repo2
  end

  it "generates a simple lockfile for a single source, gem" do
    checksums = checksums_section_when_existing do |c|
      c.checksum(gem_repo2, "myrack", "1.0.0")
    end

    install_gemfile <<-G
      source "https://gem.repo2"

      gem "myrack"
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          myrack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "updates the lockfile's bundler version if current ver. is newer, and version was forced through BUNDLER_VERSION" do
    system_gems "bundler-1.8.2"

    lockfile <<-L
      GIT
        remote: git://github.com/nex3/haml.git
        revision: 8a2271f
        specs:

      GEM
        remote: https://gem.repo2/
        specs:
          myrack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        omg!
        myrack

      BUNDLED WITH
         1.8.2
    L

    install_gemfile <<-G, verbose: true, env: { "BUNDLER_VERSION" => Bundler::VERSION }
      source "https://gem.repo2"

      gem "myrack"
    G

    expect(out).not_to include("Bundler #{Bundler::VERSION} is running, but your lockfile was generated with 1.8.2.")
    expect(out).to include("Using bundler #{Bundler::VERSION}")

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          myrack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not update the lockfile's bundler version if nothing changed during bundle install, but uses the locked version", rubygems: ">= 3.3.0.a" do
    version = "2.3.0"

    build_repo4 do
      build_gem "myrack", "1.0.0"

      build_bundler version
    end

    lockfile <<-L
      GEM
        remote: https://gem.repo4/
        specs:
          myrack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack

      BUNDLED WITH
         #{version}
    L

    install_gemfile <<-G, verbose: true, preserve_ruby_flags: true
      source "https://gem.repo4"

      gem "myrack"
    G

    expect(out).to include("Bundler #{Bundler::VERSION} is running, but your lockfile was generated with #{version}.")
    expect(out).to include("Using bundler #{version}")

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo4/
        specs:
          myrack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack

      BUNDLED WITH
         #{version}
    G
  end

  it "does not update the lockfile's bundler version if nothing changed during bundle install, and uses the latest version", rubygems: "< 3.3.0.a" do
    version = "#{Bundler::VERSION.split(".").first}.0.0.a"

    build_repo4 do
      build_gem "myrack", "1.0.0"

      build_bundler version
    end

    checksums = checksums_section do |c|
      c.checksum(gem_repo4, "myrack", "1.0.0")
    end

    lockfile <<-L
      GEM
        remote: https://gem.repo4/
        specs:
          myrack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack
      #{checksums}
      BUNDLED WITH
         #{version}
    L

    install_gemfile <<-G, verbose: true
      source "https://gem.repo4"

      gem "myrack"
    G

    expect(out).not_to include("Bundler #{Bundler::VERSION} is running, but your lockfile was generated with #{version}.")
    expect(out).to include("Using bundler #{Bundler::VERSION}")

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo4/
        specs:
          myrack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack
      #{checksums}
      BUNDLED WITH
         #{version}
    G
  end

  it "adds the BUNDLED WITH section if not present" do
    lockfile <<-L
      GEM
        remote: https://gem.repo2/
        specs:
          myrack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack
    L

    install_gemfile <<-G
      source "https://gem.repo2"

      gem "myrack", "> 0"
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          myrack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack (> 0)

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "update the bundler major version just fine" do
    current_version = Bundler::VERSION
    older_major = previous_major(current_version)

    system_gems "bundler-#{older_major}"

    lockfile <<-L
      GEM
        remote: https://gem.repo2/
        specs:
          myrack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack

      BUNDLED WITH
         #{older_major}
    L

    install_gemfile <<-G, env: { "BUNDLER_VERSION" => Bundler::VERSION }
      source "https://gem.repo2/"

      gem "myrack"
    G

    expect(err).to be_empty

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          myrack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack

      BUNDLED WITH
         #{current_version}
    G
  end

  it "generates a simple lockfile for a single source, gem with dependencies" do
    install_gemfile <<-G
      source "https://gem.repo2/"

      gem "myrack-obama"
    G

    checksums = checksums_section_when_existing do |c|
      c.checksum gem_repo2, "myrack", "1.0.0"
      c.checksum gem_repo2, "myrack-obama", "1.0"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          myrack (1.0.0)
          myrack-obama (1.0)
            myrack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack-obama
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "generates a simple lockfile for a single source, gem with a version requirement" do
    install_gemfile <<-G
      source "https://gem.repo2/"

      gem "myrack-obama", ">= 1.0"
    G

    checksums = checksums_section_when_existing do |c|
      c.checksum gem_repo2, "myrack", "1.0.0"
      c.checksum gem_repo2, "myrack-obama", "1.0"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          myrack (1.0.0)
          myrack-obama (1.0)
            myrack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack-obama (>= 1.0)
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "generates a lockfile without credentials" do
    bundle "config set https://localgemserver.test/ user:pass"

    install_gemfile(<<-G, artifice: "endpoint_strict_basic_authentication", quiet: true)
      source "https://gem.repo1"

      source "https://localgemserver.test/" do

      end

      source "https://user:pass@othergemserver.test/" do
        gem "myrack-obama", ">= 1.0"
      end
    G

    checksums = checksums_section_when_existing do |c|
      c.checksum gem_repo2, "myrack", "1.0.0"
      c.checksum gem_repo2, "myrack-obama", "1.0"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo1/
        specs:

      GEM
        remote: https://localgemserver.test/
        specs:

      GEM
        remote: https://othergemserver.test/
        specs:
          myrack (1.0.0)
          myrack-obama (1.0)
            myrack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack-obama (>= 1.0)!
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add credentials to lockfile when it does not have them already" do
    bundle "config set http://localgemserver.test/ user:pass"

    gemfile <<~G
      source "https://gem.repo1"

      source "http://localgemserver.test/" do

      end

      source "http://user:pass@othergemserver.test/" do
        gem "myrack-obama", ">= 1.0"
      end
    G

    checksums = checksums_section_when_existing do |c|
      c.checksum gem_repo2, "myrack", "1.0.0"
      c.checksum gem_repo2, "myrack-obama", "1.0"
    end

    lockfile_without_credentials = <<~L
      GEM
        remote: http://localgemserver.test/
        specs:

      GEM
        remote: http://othergemserver.test/
        specs:
          myrack (1.0.0)
          myrack-obama (1.0)
            myrack

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack-obama (>= 1.0)!
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    L

    lockfile lockfile_without_credentials

    # when not re-resolving
    bundle "install", artifice: "endpoint_strict_basic_authentication", quiet: true
    expect(lockfile).to eq lockfile_without_credentials

    # when re-resolving with full unlock
    bundle "update", artifice: "endpoint_strict_basic_authentication"
    expect(lockfile).to eq lockfile_without_credentials

    # when re-resolving without ful unlocking
    bundle "update myrack-obama", artifice: "endpoint_strict_basic_authentication"
    expect(lockfile).to eq lockfile_without_credentials
  end

  it "keeps credentials in lockfile if already there" do
    bundle "config set http://localgemserver.test/ user:pass"

    gemfile <<~G
      source "https://gem.repo1"

      source "http://localgemserver.test/" do

      end

      source "http://user:pass@othergemserver.test/" do
        gem "myrack-obama", ">= 1.0"
      end
    G

    checksums = checksums_section_when_existing do |c|
      c.checksum gem_repo2, "myrack", "1.0.0"
      c.checksum gem_repo2, "myrack-obama", "1.0"
    end

    lockfile_with_credentials = <<~L
      GEM
        remote: http://localgemserver.test/
        specs:

      GEM
        remote: http://user:pass@othergemserver.test/
        specs:
          myrack (1.0.0)
          myrack-obama (1.0)
            myrack

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack-obama (>= 1.0)!
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    L

    lockfile lockfile_with_credentials

    bundle "install", artifice: "endpoint_strict_basic_authentication", quiet: true

    expect(lockfile).to eq lockfile_with_credentials
  end

  it "generates lockfiles with multiple requirements" do
    install_gemfile <<-G
      source "https://gem.repo2/"
      gem "net-sftp"
    G

    checksums = checksums_section_when_existing do |c|
      c.checksum gem_repo2, "net-sftp", "1.1.1"
      c.checksum gem_repo2, "net-ssh", "1.0"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          net-sftp (1.1.1)
            net-ssh (>= 1.0.0, < 1.99.0)
          net-ssh (1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        net-sftp
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G

    expect(the_bundle).to include_gems "net-sftp 1.1.1", "net-ssh 1.0.0"
  end

  it "generates a simple lockfile for a single pinned source, gem with a version requirement" do
    git = build_git "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => "#{lib_path("foo-1.0")}"
    G

    checksums = checksums_section_when_existing do |c|
      c.no_checksum "foo", "1.0"
    end

    expect(lockfile).to eq <<~G
      GIT
        remote: #{lib_path("foo-1.0")}
        revision: #{git.ref_for("main")}
        specs:
          foo (1.0)

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not asplode when a platform specific dependency is present and the Gemfile has not been resolved on that platform" do
    build_lib "omg", path: lib_path("omg")

    gemfile <<-G
      source "https://gem.repo2/"

      platforms :#{not_local_tag} do
        gem "omg", :path => "#{lib_path("omg")}"
      end

      gem "myrack"
    G

    lockfile <<-L
      GIT
        remote: git://github.com/nex3/haml.git
        revision: 8a2271f
        specs:

      GEM
        remote: https://gem.repo2//
        specs:
          myrack (1.0.0)

      PLATFORMS
        #{not_local}

      DEPENDENCIES
        omg!
        myrack

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "install"
    expect(the_bundle).to include_gems "myrack 1.0.0"
  end

  it "serializes global git sources" do
    git = build_git "foo"

    checksums = checksums_section_when_existing do |c|
      c.no_checksum "foo", "1.0"
    end

    install_gemfile <<-G
      source "https://gem.repo1"
      git "#{lib_path("foo-1.0")}" do
        gem "foo"
      end
    G

    expect(lockfile).to eq <<~G
      GIT
        remote: #{lib_path("foo-1.0")}
        revision: #{git.ref_for("main")}
        specs:
          foo (1.0)

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "generates a lockfile with a ref for a single pinned source, git gem with a branch requirement" do
    git = build_git "foo"
    update_git "foo", branch: "omg"

    checksums = checksums_section_when_existing do |c|
      c.no_checksum "foo", "1.0"
    end

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => "#{lib_path("foo-1.0")}", :branch => "omg"
    G

    expect(lockfile).to eq <<~G
      GIT
        remote: #{lib_path("foo-1.0")}
        revision: #{git.ref_for("omg")}
        branch: omg
        specs:
          foo (1.0)

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "generates a lockfile with a ref for a single pinned source, git gem with a tag requirement" do
    git = build_git "foo"
    update_git "foo", tag: "omg"

    checksums = checksums_section_when_existing do |c|
      c.no_checksum "foo", "1.0"
    end

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => "#{lib_path("foo-1.0")}", :tag => "omg"
    G

    expect(lockfile).to eq <<~G
      GIT
        remote: #{lib_path("foo-1.0")}
        revision: #{git.ref_for("omg")}
        tag: omg
        specs:
          foo (1.0)

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "is conservative with dependencies of git gems" do
    build_repo4 do
      build_gem "orm_adapter", "0.4.1"
      build_gem "orm_adapter", "0.5.0"
    end

    FileUtils.mkdir_p lib_path("ckeditor/lib")

    @remote = build_git("ckeditor_remote", bare: true)

    build_git "ckeditor", path: lib_path("ckeditor") do |s|
      s.write "lib/ckeditor.rb", "CKEDITOR = '4.0.7'"
      s.version = "4.0.7"
      s.add_dependency "orm_adapter"
    end

    update_git "ckeditor", path: lib_path("ckeditor"), remote: @remote.path
    update_git "ckeditor", path: lib_path("ckeditor"), tag: "v4.0.7"
    old_git = update_git "ckeditor", path: lib_path("ckeditor"), push: "v4.0.7"

    update_git "ckeditor", path: lib_path("ckeditor"), gemspec: true do |s|
      s.write "lib/ckeditor.rb", "CKEDITOR = '4.0.8'"
      s.version = "4.0.8"
      s.add_dependency "orm_adapter"
    end
    update_git "ckeditor", path: lib_path("ckeditor"), tag: "v4.0.8"

    new_git = update_git "ckeditor", path: lib_path("ckeditor"), push: "v4.0.8"

    gemfile <<-G
      source "https://gem.repo4"
      gem "ckeditor", :git => "#{@remote.path}", :tag => "v4.0.8"
    G

    lockfile <<~L
      GIT
        remote: #{@remote.path}
        revision: #{old_git.ref_for("v4.0.7")}
        tag: v4.0.7
        specs:
          ckeditor (4.0.7)
            orm_adapter

      GEM
        remote: https://gem.repo4/
        specs:
          orm_adapter (0.4.1)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        ckeditor!

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "lock"

    # Bumps the git gem, but keeps its dependency locked
    expect(lockfile).to eq <<~L
      GIT
        remote: #{@remote.path}
        revision: #{new_git.ref_for("v4.0.8")}
        tag: v4.0.8
        specs:
          ckeditor (4.0.8)
            orm_adapter

      GEM
        remote: https://gem.repo4/
        specs:
          orm_adapter (0.4.1)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        ckeditor!

      BUNDLED WITH
         #{Bundler::VERSION}
    L
  end

  it "serializes pinned path sources to the lockfile" do
    build_lib "foo"

    checksums = checksums_section_when_existing do |c|
      c.no_checksum "foo", "1.0"
    end

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => "#{lib_path("foo-1.0")}"
    G

    expect(lockfile).to eq <<~G
      PATH
        remote: #{lib_path("foo-1.0")}
        specs:
          foo (1.0)

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "serializes pinned path sources to the lockfile even when packaging" do
    build_lib "foo"

    checksums = checksums_section_when_existing do |c|
      c.no_checksum "foo", "1.0"
    end

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => "#{lib_path("foo-1.0")}"
    G

    bundle "config set cache_all true"
    bundle :cache
    bundle :install, local: true

    expect(lockfile).to eq <<~G
      PATH
        remote: #{lib_path("foo-1.0")}
        specs:
          foo (1.0)

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "sorts serialized sources by type" do
    build_lib "foo"
    bar = build_git "bar"

    checksums = checksums_section_when_existing do |c|
      c.no_checksum "foo", "1.0"
      c.no_checksum "bar", "1.0"
      c.checksum gem_repo2, "myrack", "1.0.0"
    end

    install_gemfile <<-G
      source "https://gem.repo2/"

      gem "myrack"
      gem "foo", :path => "#{lib_path("foo-1.0")}"
      gem "bar", :git => "#{lib_path("bar-1.0")}"
    G

    expect(lockfile).to eq <<~G
      GIT
        remote: #{lib_path("bar-1.0")}
        revision: #{bar.ref_for("main")}
        specs:
          bar (1.0)

      PATH
        remote: #{lib_path("foo-1.0")}
        specs:
          foo (1.0)

      GEM
        remote: https://gem.repo2/
        specs:
          myrack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        bar!
        foo!
        myrack
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "removes redundant sources" do
    install_gemfile <<-G
      source "https://gem.repo2/"

      gem "myrack", :source => "https://gem.repo2/"
    G

    checksums = checksums_section_when_existing do |c|
      c.checksum gem_repo2, "myrack", "1.0.0"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          myrack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack!
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "lists gems alphabetically" do
    install_gemfile <<-G
      source "https://gem.repo2/"

      gem "thin"
      gem "actionpack"
      gem "myrack-obama"
    G

    checksums = checksums_section_when_existing do |c|
      c.checksum gem_repo2, "actionpack", "2.3.2"
      c.checksum gem_repo2, "activesupport", "2.3.2"
      c.checksum gem_repo2, "myrack", "1.0.0"
      c.checksum gem_repo2, "myrack-obama", "1.0"
      c.checksum gem_repo2, "thin", "1.0"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          actionpack (2.3.2)
            activesupport (= 2.3.2)
          activesupport (2.3.2)
          myrack (1.0.0)
          myrack-obama (1.0)
            myrack
          thin (1.0)
            myrack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        actionpack
        myrack-obama
        thin
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "orders dependencies' dependencies in alphabetical order" do
    install_gemfile <<-G
      source "https://gem.repo2/"

      gem "rails"
    G

    checksums = checksums_section_when_existing do |c|
      c.checksum gem_repo2, "actionmailer", "2.3.2"
      c.checksum gem_repo2, "actionpack", "2.3.2"
      c.checksum gem_repo2, "activerecord", "2.3.2"
      c.checksum gem_repo2, "activeresource", "2.3.2"
      c.checksum gem_repo2, "activesupport", "2.3.2"
      c.checksum gem_repo2, "rails", "2.3.2"
      c.checksum gem_repo2, "rake", rake_version
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          actionmailer (2.3.2)
            activesupport (= 2.3.2)
          actionpack (2.3.2)
            activesupport (= 2.3.2)
          activerecord (2.3.2)
            activesupport (= 2.3.2)
          activeresource (2.3.2)
            activesupport (= 2.3.2)
          activesupport (2.3.2)
          rails (2.3.2)
            actionmailer (= 2.3.2)
            actionpack (= 2.3.2)
            activerecord (= 2.3.2)
            activeresource (= 2.3.2)
            rake (= #{rake_version})
          rake (#{rake_version})

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rails
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "orders dependencies by version" do
    update_repo2 do
      # Capistrano did this (at least until version 2.5.10)
      # RubyGems 2.2 doesn't allow the specifying of a dependency twice
      # See https://github.com/rubygems/rubygems/commit/03dbac93a3396a80db258d9bc63500333c25bd2f
      build_gem "double_deps", "1.0", skip_validation: true do |s|
        s.add_dependency "net-ssh", ">= 1.0.0"
        s.add_dependency "net-ssh"
      end
    end

    install_gemfile <<-G
      source "https://gem.repo2"
      gem 'double_deps'
    G

    checksums = checksums_section_when_existing do |c|
      c.checksum gem_repo2, "double_deps", "1.0"
      c.checksum gem_repo2, "net-ssh", "1.0"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          double_deps (1.0)
            net-ssh
            net-ssh (>= 1.0.0)
          net-ssh (1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        double_deps
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add the :require option to the lockfile" do
    install_gemfile <<-G
      source "https://gem.repo2/"

      gem "myrack-obama", ">= 1.0", :require => "myrack/obama"
    G

    checksums = checksums_section_when_existing do |c|
      c.checksum gem_repo2, "myrack", "1.0.0"
      c.checksum gem_repo2, "myrack-obama", "1.0"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          myrack (1.0.0)
          myrack-obama (1.0)
            myrack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack-obama (>= 1.0)
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add the :group option to the lockfile" do
    install_gemfile <<-G
      source "https://gem.repo2/"

      gem "myrack-obama", ">= 1.0", :group => :test
    G

    checksums = checksums_section_when_existing do |c|
      c.checksum gem_repo2, "myrack", "1.0.0"
      c.checksum gem_repo2, "myrack-obama", "1.0"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          myrack (1.0.0)
          myrack-obama (1.0)
            myrack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack-obama (>= 1.0)
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "stores relative paths when the path is provided in a relative fashion and in Gemfile dir" do
    build_lib "foo", path: bundled_app("foo")

    checksums = checksums_section_when_existing do |c|
      c.no_checksum "foo", "1.0"
    end

    install_gemfile <<-G
      source "https://gem.repo1"
      path "foo" do
        gem "foo"
      end
    G

    expect(lockfile).to eq <<~G
      PATH
        remote: foo
        specs:
          foo (1.0)

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "stores relative paths when the path is provided in a relative fashion and is above Gemfile dir" do
    build_lib "foo", path: bundled_app(File.join("..", "foo"))

    checksums = checksums_section_when_existing do |c|
      c.no_checksum "foo", "1.0"
    end

    install_gemfile <<-G
      source "https://gem.repo1"
      path "../foo" do
        gem "foo"
      end
    G

    expect(lockfile).to eq <<~G
      PATH
        remote: ../foo
        specs:
          foo (1.0)

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "stores relative paths when the path is provided in an absolute fashion but is relative" do
    build_lib "foo", path: bundled_app("foo")

    checksums = checksums_section_when_existing do |c|
      c.no_checksum "foo", "1.0"
    end

    install_gemfile <<-G
      source "https://gem.repo1"
      path File.expand_path("foo", __dir__) do
        gem "foo"
      end
    G

    expect(lockfile).to eq <<~G
      PATH
        remote: foo
        specs:
          foo (1.0)

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "stores relative paths when the path is provided for gemspec" do
    build_lib("foo", path: tmp("foo"))

    checksums = checksums_section_when_existing do |c|
      c.no_checksum "foo", "1.0"
    end

    install_gemfile <<-G
      source "https://gem.repo1"
      gemspec :path => "../foo"
    G

    expect(lockfile).to eq <<~G
      PATH
        remote: ../foo
        specs:
          foo (1.0)

      GEM
        remote: https://gem.repo1/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "keeps existing platforms in the lockfile" do
    checksums = checksums_section_when_existing do |c|
      c.no_checksum "myrack", "1.0.0"
    end

    lockfile <<-G
      GEM
        remote: https://gem.repo2/
        specs:
          myrack (1.0.0)

      PLATFORMS
        java

      DEPENDENCIES
        myrack
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G

    install_gemfile <<-G
      source "https://gem.repo2/"

      gem "myrack"
    G

    checksums.checksum(gem_repo2, "myrack", "1.0.0")

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          myrack (1.0.0)

      PLATFORMS
        #{lockfile_platforms("java", local_platform, defaults: [])}

      DEPENDENCIES
        myrack
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "adds compatible platform specific variants to the lockfile, even if resolution fallback to RUBY due to some other incompatible platform specific variant" do
    simulate_platform "arm64-darwin-23" do
      build_repo4 do
        build_gem "google-protobuf", "3.25.1"
        build_gem "google-protobuf", "3.25.1" do |s|
          s.platform = "arm64-darwin-23"
        end
        build_gem "google-protobuf", "3.25.1" do |s|
          s.platform = "x64-mingw-ucrt"
          s.required_ruby_version = "> #{Gem.ruby_version}"
        end
      end

      gemfile <<-G
        source "https://gem.repo4"
        gem "google-protobuf"
      G
      bundle "lock --add-platform x64-mingw-ucrt"

      expect(lockfile).to eq <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            google-protobuf (3.25.1)
            google-protobuf (3.25.1-arm64-darwin-23)

        PLATFORMS
          arm64-darwin-23
          ruby
          x64-mingw-ucrt

        DEPENDENCIES
          google-protobuf

        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end
  end

  it "persists the spec's specific platform to the lockfile" do
    build_repo2 do
      build_gem "platform_specific", "1.0" do |s|
        s.platform = Gem::Platform.new("universal-java-16")
      end
    end

    simulate_platform "universal-java-16"

    install_gemfile <<-G
      source "https://gem.repo2"
      gem "platform_specific"
    G

    checksums = checksums_section_when_existing do |c|
      c.checksum gem_repo2, "platform_specific", "1.0", "universal-java-16"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          platform_specific (1.0-universal-java-16)

      PLATFORMS
        universal-java-16

      DEPENDENCIES
        platform_specific
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add duplicate gems" do
    checksums = checksums_section_when_existing do |c|
      c.checksum(gem_repo2, "activesupport", "2.3.5")
      c.checksum(gem_repo2, "myrack", "1.0.0")
    end

    install_gemfile <<-G
      source "https://gem.repo2/"
      gem "myrack"
    G

    install_gemfile <<-G
      source "https://gem.repo2/"
      gem "myrack"
      gem "activesupport"
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          activesupport (2.3.5)
          myrack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        activesupport
        myrack
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add duplicate dependencies" do
    checksums = checksums_section_when_existing do |c|
      c.checksum(gem_repo2, "myrack", "1.0.0")
    end

    install_gemfile <<-G
      source "https://gem.repo2/"
      gem "myrack"
      gem "myrack"
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          myrack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add duplicate dependencies with versions" do
    checksums = checksums_section_when_existing do |c|
      c.checksum(gem_repo2, "myrack", "1.0.0")
    end

    install_gemfile <<-G
      source "https://gem.repo2/"
      gem "myrack", "1.0"
      gem "myrack", "1.0"
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          myrack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack (= 1.0)
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add duplicate dependencies in different groups" do
    checksums = checksums_section_when_existing do |c|
      c.checksum(gem_repo2, "myrack", "1.0.0")
    end

    install_gemfile <<-G
      source "https://gem.repo2/"
      gem "myrack", "1.0", :group => :one
      gem "myrack", "1.0", :group => :two
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          myrack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack (= 1.0)
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "raises if two different versions are used" do
    install_gemfile <<-G, raise_on_error: false
      source "https://gem.repo2/"
      gem "myrack", "1.0"
      gem "myrack", "1.1"
    G

    expect(bundled_app_lock).not_to exist
    expect(err).to include "myrack (= 1.0) and myrack (= 1.1)"
  end

  it "raises if two different sources are used" do
    install_gemfile <<-G, raise_on_error: false
      source "https://gem.repo2/"
      gem "myrack"
      gem "myrack", :git => "git://hubz.com"
    G

    expect(bundled_app_lock).not_to exist
    expect(err).to include "myrack (>= 0) should come from an unspecified source and git://hubz.com"
  end

  it "works correctly with multiple version dependencies" do
    checksums = checksums_section_when_existing do |c|
      c.checksum(gem_repo2, "myrack", "0.9.1")
    end

    install_gemfile <<-G
      source "https://gem.repo2/"
      gem "myrack", "> 0.9", "< 1.0"
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          myrack (0.9.1)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack (> 0.9, < 1.0)
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "captures the Ruby version in the lockfile" do
    checksums = checksums_section_when_existing do |c|
      c.checksum(gem_repo2, "myrack", "0.9.1")
    end

    install_gemfile <<-G
      source "https://gem.repo2/"
      ruby '#{Gem.ruby_version}'
      gem "myrack", "> 0.9", "< 1.0"
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo2/
        specs:
          myrack (0.9.1)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack (> 0.9, < 1.0)
      #{checksums}
      RUBY VERSION
         #{Bundler::RubyVersion.system}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "raises a helpful error message when the lockfile is missing deps" do
    lockfile <<-L
      GEM
        remote: https://gem.repo2/
        specs:
          myrack_middleware (1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack_middleware
    L

    install_gemfile <<-G, raise_on_error: false
      source "https://gem.repo2"
      gem "myrack_middleware"
    G

    expect(err).to include("Downloading myrack_middleware-1.0 revealed dependencies not in the API or the lockfile (#{Gem::Dependency.new("myrack", "= 0.9.1")}).").
      and include("Running `bundle update myrack_middleware` should fix the problem.")
  end

  it "regenerates a lockfile with no specs" do
    build_repo4 do
      build_gem "indirect_dependency", "1.2.3" do |s|
        s.metadata["funding_uri"] = "https://example.com/donate"
      end

      build_gem "direct_dependency", "4.5.6" do |s|
        s.add_dependency "indirect_dependency", ">= 0"
      end
    end

    lockfile <<-G
      GEM
        remote: https://gem.repo4/
        specs:

      PLATFORMS
        ruby

      DEPENDENCIES
        direct_dependency

      BUNDLED WITH
         #{Bundler::VERSION}
    G

    install_gemfile <<-G
      source "https://gem.repo4"

      gem "direct_dependency"
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: https://gem.repo4/
        specs:
          direct_dependency (4.5.6)
            indirect_dependency
          indirect_dependency (1.2.3)

      PLATFORMS
        #{lockfile_platforms("ruby", generic_local_platform, defaults: [])}

      DEPENDENCIES
        direct_dependency

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  shared_examples_for "a lockfile missing dependent specs" do
    it "auto-heals" do
      build_repo4 do
        build_gem "minitest-bisect", "1.6.0" do |s|
          s.add_dependency "path_expander", "~> 1.1"
        end

        build_gem "path_expander", "1.1.1"
      end

      gemfile <<~G
        source "https://gem.repo4"
        gem "minitest-bisect"
      G

      # Corrupt lockfile (completely missing path_expander)
      lockfile <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            minitest-bisect (1.6.0)

        PLATFORMS
          #{platforms}

        DEPENDENCIES
          minitest-bisect

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      cache_gems "minitest-bisect-1.6.0", "path_expander-1.1.1", gem_repo: gem_repo4
      bundle :install

      expect(lockfile).to eq <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            minitest-bisect (1.6.0)
              path_expander (~> 1.1)
            path_expander (1.1.1)

        PLATFORMS
          #{platforms}

        DEPENDENCIES
          minitest-bisect

        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end
  end

  context "with just specific platform" do
    let(:platforms) { lockfile_platforms }

    it_behaves_like "a lockfile missing dependent specs"
  end

  context "with both ruby and specific platform" do
    let(:platforms) { lockfile_platforms("ruby") }

    it_behaves_like "a lockfile missing dependent specs"
  end

  it "auto-heals when the lockfile is missing specs" do
    build_repo4 do
      build_gem "minitest-bisect", "1.6.0" do |s|
        s.add_dependency "path_expander", "~> 1.1"
      end

      build_gem "path_expander", "1.1.1"
    end

    gemfile <<~G
      source "https://gem.repo4"
      gem "minitest-bisect"
    G

    lockfile <<~L
      GEM
        remote: https://gem.repo4/
        specs:
          minitest-bisect (1.6.0)
            path_expander (~> 1.1)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        minitest-bisect

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "install --verbose"
    expect(out).to include("re-resolving dependencies because your lock file includes \"minitest-bisect\" but not some of its dependencies")

    expect(lockfile).to eq <<~L
      GEM
        remote: https://gem.repo4/
        specs:
          minitest-bisect (1.6.0)
            path_expander (~> 1.1)
          path_expander (1.1.1)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        minitest-bisect

      BUNDLED WITH
         #{Bundler::VERSION}
    L
  end

  describe "a line ending" do
    def set_lockfile_mtime_to_known_value
      time = Time.local(2000, 1, 1, 0, 0, 0)
      File.utime(time, time, bundled_app_lock)
    end
    before(:each) do
      build_repo2

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "myrack"
      G
      set_lockfile_mtime_to_known_value
    end

    it "generates Gemfile.lock with \\n line endings" do
      expect(File.read(bundled_app_lock)).not_to match("\r\n")
      expect(the_bundle).to include_gems "myrack 1.0"
    end

    context "during updates" do
      it "preserves Gemfile.lock \\n line endings" do
        update_repo2 do
          build_gem "myrack", "1.2" do |s|
            s.executables = "myrackup"
          end
        end

        expect { bundle "update", all: true }.to change { File.mtime(bundled_app_lock) }
        expect(File.read(bundled_app_lock)).not_to match("\r\n")
        expect(the_bundle).to include_gems "myrack 1.2"
      end

      it "preserves Gemfile.lock \\n\\r line endings" do
        skip "needs to be adapted" if Gem.win_platform?

        update_repo2 do
          build_gem "myrack", "1.2" do |s|
            s.executables = "myrackup"
          end
        end

        win_lock = File.read(bundled_app_lock).gsub(/\n/, "\r\n")
        File.open(bundled_app_lock, "wb") {|f| f.puts(win_lock) }
        set_lockfile_mtime_to_known_value

        expect { bundle "update", all: true }.to change { File.mtime(bundled_app_lock) }
        expect(File.read(bundled_app_lock)).to match("\r\n")

        expect(the_bundle).to include_gems "myrack 1.2"
      end
    end

    context "when nothing changes" do
      it "preserves Gemfile.lock \\n line endings" do
        expect do
          ruby <<-RUBY
                   require 'bundler'
                   Bundler.setup
                 RUBY
        end.not_to change { File.mtime(bundled_app_lock) }
      end

      it "preserves Gemfile.lock \\n\\r line endings" do
        win_lock = File.read(bundled_app_lock).gsub(/\n/, "\r\n")
        File.open(bundled_app_lock, "wb") {|f| f.puts(win_lock) }
        set_lockfile_mtime_to_known_value

        expect do
          ruby <<-RUBY
                   require 'bundler'
                   Bundler.setup
                 RUBY
        end.not_to change { File.mtime(bundled_app_lock) }
      end
    end
  end

  it "refuses to install if Gemfile.lock contains conflict markers" do
    lockfile <<-L
      GEM
        remote: https://gem.repo2//
        specs:
      <<<<<<<
          myrack (1.0.0)
      =======
          myrack (1.0.1)
      >>>>>>>

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    install_gemfile <<-G, raise_on_error: false
      source "https://gem.repo2/"
      gem "myrack"
    G

    expect(err).to match(/your Gemfile.lock contains merge conflicts/i)
    expect(err).to match(/git checkout HEAD -- Gemfile.lock/i)
  end

  private

  def prerelease?(version)
    Gem::Version.new(version).prerelease?
  end

  def previous_major(version)
    version.split(".").map.with_index {|v, i| i == 0 ? v.to_i - 1 : v }.join(".")
  end

  def bump_minor(version)
    bump(version, 1)
  end

  def bump(version, segment)
    version.split(".").map.with_index {|v, i| i == segment ? v.to_i + 1 : v }.join(".")
  end
end
