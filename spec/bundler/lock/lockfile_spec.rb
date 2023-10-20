# frozen_string_literal: true

RSpec.describe "the lockfile format" do
  before do
    build_repo2
  end

  it "generates a simple lockfile for a single source, gem" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"

      gem "rack"
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack

      CHECKSUMS
        #{checksum_for_repo_gem(gem_repo2, "rack", "1.0.0")}

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
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        omg!
        rack

      BUNDLED WITH
         1.8.2
    L

    install_gemfile <<-G, :verbose => true, :env => { "BUNDLER_VERSION" => Bundler::VERSION }
      source "#{file_uri_for(gem_repo2)}"

      gem "rack"
    G

    expect(out).not_to include("Bundler #{Bundler::VERSION} is running, but your lockfile was generated with 1.8.2.")
    expect(out).to include("Using bundler #{Bundler::VERSION}")

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack

      CHECKSUMS
        #{checksum_for_repo_gem(gem_repo2, "rack", "1.0.0")}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not update the lockfile's bundler version if nothing changed during bundle install, but uses the locked version", :rubygems => ">= 3.3.0.a", :realworld => true do
    version = "2.3.0"

    lockfile <<-L
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack

      BUNDLED WITH
         #{version}
    L

    install_gemfile <<-G, :verbose => true, :artifice => "vcr"
      source "#{file_uri_for(gem_repo2)}"

      gem "rack"
    G

    expect(out).to include("Bundler #{Bundler::VERSION} is running, but your lockfile was generated with #{version}.")
    expect(out).to include("Using bundler #{version}")

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack

      BUNDLED WITH
         #{version}
    G
  end

  it "does not update the lockfile's bundler version if nothing changed during bundle install, and uses the latest version", :rubygems => "< 3.3.0.a" do
    version = "#{Bundler::VERSION.split(".").first}.0.0.a"

    lockfile <<-L
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack

      CHECKSUMS
        #{checksum_for_repo_gem(gem_repo2, "rack", "1.0.0")}

      BUNDLED WITH
         #{version}
    L

    install_gemfile <<-G, :verbose => true
      source "#{file_uri_for(gem_repo2)}"

      gem "rack"
    G

    expect(out).not_to include("Bundler #{Bundler::VERSION} is running, but your lockfile was generated with #{version}.")
    expect(out).to include("Using bundler #{Bundler::VERSION}")

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack

      CHECKSUMS
        #{checksum_for_repo_gem(gem_repo2, "rack", "1.0.0")}

      BUNDLED WITH
         #{version}
    G
  end

  it "adds the BUNDLED WITH section if not present" do
    lockfile <<-L
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack
    L

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"

      gem "rack", "> 0"
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack (> 0)

      CHECKSUMS
        #{checksum_for_repo_gem(gem_repo2, "rack", "1.0.0")}

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
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack

      BUNDLED WITH
         #{older_major}
    L

    install_gemfile <<-G, :env => { "BUNDLER_VERSION" => Bundler::VERSION }
      source "#{file_uri_for(gem_repo2)}/"

      gem "rack"
    G

    expect(err).to be_empty

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack

      CHECKSUMS
        #{checksum_for_repo_gem(gem_repo2, "rack", "1.0.0")}

      BUNDLED WITH
         #{current_version}
    G
  end

  it "generates a simple lockfile for a single source, gem with dependencies" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"

      gem "rack-obama"
    G

    expected_checksums = checksum_section do |c|
      c.repo_gem gem_repo2, "rack", "1.0.0"
      c.repo_gem gem_repo2, "rack-obama", "1.0"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)
          rack-obama (1.0)
            rack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack-obama

      CHECKSUMS
        #{expected_checksums}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "generates a simple lockfile for a single source, gem with a version requirement" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"

      gem "rack-obama", ">= 1.0"
    G

    expected_checksums = checksum_section do |c|
      c.repo_gem gem_repo2, "rack", "1.0.0"
      c.repo_gem gem_repo2, "rack-obama", "1.0"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)
          rack-obama (1.0)
            rack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack-obama (>= 1.0)

      CHECKSUMS
        #{expected_checksums}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "generates a lockfile without credentials for a configured source" do
    bundle "config set http://localgemserver.test/ user:pass"

    install_gemfile(<<-G, :artifice => "endpoint_strict_basic_authentication", :quiet => true)
      source "#{file_uri_for(gem_repo1)}"

      source "http://localgemserver.test/" do

      end

      source "http://user:pass@othergemserver.test/" do
        gem "rack-obama", ">= 1.0"
      end
    G

    expected_checksums = checksum_section do |c|
      c.repo_gem gem_repo2, "rack", "1.0.0"
      c.repo_gem gem_repo2, "rack-obama", "1.0"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo1)}/
        specs:

      GEM
        remote: http://localgemserver.test/
        specs:

      GEM
        remote: http://user:pass@othergemserver.test/
        specs:
          rack (1.0.0)
          rack-obama (1.0)
            rack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack-obama (>= 1.0)!

      CHECKSUMS
        #{expected_checksums}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "generates lockfiles with multiple requirements" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"
      gem "net-sftp"
    G

    expected_checksums = checksum_section do |c|
      c.repo_gem gem_repo2, "net-sftp", "1.1.1"
      c.repo_gem gem_repo2, "net-ssh", "1.0"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          net-sftp (1.1.1)
            net-ssh (>= 1.0.0, < 1.99.0)
          net-ssh (1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        net-sftp

      CHECKSUMS
        #{expected_checksums}

      BUNDLED WITH
         #{Bundler::VERSION}
    G

    expect(the_bundle).to include_gems "net-sftp 1.1.1", "net-ssh 1.0.0"
  end

  it "generates a simple lockfile for a single pinned source, gem with a version requirement" do
    git = build_git "foo"

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "foo", :git => "#{lib_path("foo-1.0")}"
    G

    expect(lockfile).to eq <<~G
      GIT
        remote: #{lib_path("foo-1.0")}
        revision: #{git.ref_for("main")}
        specs:
          foo (1.0)

      GEM
        remote: #{file_uri_for(gem_repo1)}/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      CHECKSUMS
        foo (1.0)

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not asplode when a platform specific dependency is present and the Gemfile has not been resolved on that platform" do
    build_lib "omg", :path => lib_path("omg")

    gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"

      platforms :#{not_local_tag} do
        gem "omg", :path => "#{lib_path("omg")}"
      end

      gem "rack"
    G

    lockfile <<-L
      GIT
        remote: git://github.com/nex3/haml.git
        revision: 8a2271f
        specs:

      GEM
        remote: #{file_uri_for(gem_repo2)}//
        specs:
          rack (1.0.0)

      PLATFORMS
        #{not_local}

      DEPENDENCIES
        omg!
        rack

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "install"
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "serializes global git sources" do
    git = build_git "foo"

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
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
        remote: #{file_uri_for(gem_repo1)}/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      CHECKSUMS
        foo (1.0)

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "generates a lockfile with a ref for a single pinned source, git gem with a branch requirement" do
    git = build_git "foo"
    update_git "foo", :branch => "omg"

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
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
        remote: #{file_uri_for(gem_repo1)}/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      CHECKSUMS
        foo (1.0)

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "generates a lockfile with a ref for a single pinned source, git gem with a tag requirement" do
    git = build_git "foo"
    update_git "foo", :tag => "omg"

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
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
        remote: #{file_uri_for(gem_repo1)}/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      CHECKSUMS
        foo (1.0)

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

    @remote = build_git("ckeditor_remote", :bare => true)

    build_git "ckeditor", :path => lib_path("ckeditor") do |s|
      s.write "lib/ckeditor.rb", "CKEDITOR = '4.0.7'"
      s.version = "4.0.7"
      s.add_dependency "orm_adapter"
    end

    update_git "ckeditor", :path => lib_path("ckeditor"), :remote => file_uri_for(@remote.path)
    update_git "ckeditor", :path => lib_path("ckeditor"), :tag => "v4.0.7"
    old_git = update_git "ckeditor", :path => lib_path("ckeditor"), :push => "v4.0.7"

    update_git "ckeditor", :path => lib_path("ckeditor"), :gemspec => true do |s|
      s.write "lib/ckeditor.rb", "CKEDITOR = '4.0.8'"
      s.version = "4.0.8"
      s.add_dependency "orm_adapter"
    end
    update_git "ckeditor", :path => lib_path("ckeditor"), :tag => "v4.0.8"

    new_git = update_git "ckeditor", :path => lib_path("ckeditor"), :push => "v4.0.8"

    gemfile <<-G
      source "#{file_uri_for(gem_repo4)}"
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
        remote: #{file_uri_for(gem_repo4)}/
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
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          orm_adapter (0.4.1)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        ckeditor!

      CHECKSUMS
        #{gem_no_checksum "ckeditor", "4.0.8"}
        #{gem_no_checksum "orm_adapter", "0.4.1"}

      BUNDLED WITH
         #{Bundler::VERSION}
    L
  end

  it "serializes pinned path sources to the lockfile" do
    build_lib "foo"

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "foo", :path => "#{lib_path("foo-1.0")}"
    G

    expect(lockfile).to eq <<~G
      PATH
        remote: #{lib_path("foo-1.0")}
        specs:
          foo (1.0)

      GEM
        remote: #{file_uri_for(gem_repo1)}/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      CHECKSUMS
        foo (1.0)

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "serializes pinned path sources to the lockfile even when packaging" do
    build_lib "foo"

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "foo", :path => "#{lib_path("foo-1.0")}"
    G

    bundle "config set cache_all true"
    bundle :cache
    bundle :install, :local => true

    expect(lockfile).to eq <<~G
      PATH
        remote: #{lib_path("foo-1.0")}
        specs:
          foo (1.0)

      GEM
        remote: #{file_uri_for(gem_repo1)}/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      CHECKSUMS
        foo (1.0)

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "sorts serialized sources by type" do
    build_lib "foo"
    bar = build_git "bar"

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"

      gem "rack"
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
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        bar!
        foo!
        rack

      CHECKSUMS
        bar (1.0)
        foo (1.0)
        #{checksum_for_repo_gem gem_repo2, "rack", "1.0.0"}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "removes redundant sources" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"

      gem "rack", :source => "#{file_uri_for(gem_repo2)}/"
    G

    expected_checksums = checksum_section do |c|
      c.repo_gem gem_repo2, "rack", "1.0.0"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack!

      CHECKSUMS
        #{expected_checksums}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "lists gems alphabetically" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"

      gem "thin"
      gem "actionpack"
      gem "rack-obama"
    G

    expected_checksums = checksum_section do |c|
      c.repo_gem gem_repo2, "actionpack", "2.3.2"
      c.repo_gem gem_repo2, "activesupport", "2.3.2"
      c.repo_gem gem_repo2, "rack", "1.0.0"
      c.repo_gem gem_repo2, "rack-obama", "1.0"
      c.repo_gem gem_repo2, "thin", "1.0"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          actionpack (2.3.2)
            activesupport (= 2.3.2)
          activesupport (2.3.2)
          rack (1.0.0)
          rack-obama (1.0)
            rack
          thin (1.0)
            rack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        actionpack
        rack-obama
        thin

      CHECKSUMS
        #{expected_checksums}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "orders dependencies' dependencies in alphabetical order" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"

      gem "rails"
    G

    expected_checksums = checksum_section do |c|
      c.repo_gem gem_repo2, "actionmailer", "2.3.2"
      c.repo_gem gem_repo2, "actionpack", "2.3.2"
      c.repo_gem gem_repo2, "activerecord", "2.3.2"
      c.repo_gem gem_repo2, "activeresource", "2.3.2"
      c.repo_gem gem_repo2, "activesupport", "2.3.2"
      c.repo_gem gem_repo2, "rails", "2.3.2"
      c.repo_gem gem_repo2, "rake", "13.0.1"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
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
            rake (= 13.0.1)
          rake (13.0.1)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rails

      CHECKSUMS
        #{expected_checksums}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "orders dependencies by version" do
    update_repo2 do
      # Capistrano did this (at least until version 2.5.10)
      # RubyGems 2.2 doesn't allow the specifying of a dependency twice
      # See https://github.com/rubygems/rubygems/commit/03dbac93a3396a80db258d9bc63500333c25bd2f
      build_gem "double_deps", "1.0", :skip_validation => true do |s|
        s.add_dependency "net-ssh", ">= 1.0.0"
        s.add_dependency "net-ssh"
      end
    end

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"
      gem 'double_deps'
    G

    expected_checksums = checksum_section do |c|
      c.repo_gem gem_repo2, "double_deps", "1.0"
      c.repo_gem gem_repo2, "net-ssh", "1.0"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          double_deps (1.0)
            net-ssh
            net-ssh (>= 1.0.0)
          net-ssh (1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        double_deps

      CHECKSUMS
        #{expected_checksums}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add the :require option to the lockfile" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"

      gem "rack-obama", ">= 1.0", :require => "rack/obama"
    G

    expected_checksums = checksum_section do |c|
      c.repo_gem gem_repo2, "rack", "1.0.0"
      c.repo_gem gem_repo2, "rack-obama", "1.0"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)
          rack-obama (1.0)
            rack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack-obama (>= 1.0)

      CHECKSUMS
        #{expected_checksums}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add the :group option to the lockfile" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"

      gem "rack-obama", ">= 1.0", :group => :test
    G

    expected_checksums = checksum_section do |c|
      c.repo_gem gem_repo2, "rack", "1.0.0"
      c.repo_gem gem_repo2, "rack-obama", "1.0"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)
          rack-obama (1.0)
            rack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack-obama (>= 1.0)

      CHECKSUMS
        #{expected_checksums}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "stores relative paths when the path is provided in a relative fashion and in Gemfile dir" do
    build_lib "foo", :path => bundled_app("foo")

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
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
        remote: #{file_uri_for(gem_repo1)}/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      CHECKSUMS
        foo (1.0)

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "stores relative paths when the path is provided in a relative fashion and is above Gemfile dir" do
    build_lib "foo", :path => bundled_app(File.join("..", "foo"))

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
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
        remote: #{file_uri_for(gem_repo1)}/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      CHECKSUMS
        foo (1.0)

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "stores relative paths when the path is provided in an absolute fashion but is relative" do
    build_lib "foo", :path => bundled_app("foo")

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
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
        remote: #{file_uri_for(gem_repo1)}/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      CHECKSUMS
        foo (1.0)

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "stores relative paths when the path is provided for gemspec" do
    build_lib("foo", :path => tmp.join("foo"))

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gemspec :path => "../foo"
    G

    expect(lockfile).to eq <<~G
      PATH
        remote: ../foo
        specs:
          foo (1.0)

      GEM
        remote: #{file_uri_for(gem_repo1)}/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      CHECKSUMS
        foo (1.0)

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "keeps existing platforms in the lockfile" do
    lockfile <<-G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        java

      DEPENDENCIES
        rack

      BUNDLED WITH
         #{Bundler::VERSION}
    G

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"

      gem "rack"
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms("java")}

      DEPENDENCIES
        rack

      CHECKSUMS
        #{checksum_for_repo_gem(gem_repo2, "rack", "1.0.0")}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "persists the spec's specific platform to the lockfile" do
    build_repo2 do
      build_gem "platform_specific", "1.0" do |s|
        s.platform = Gem::Platform.new("universal-java-16")
      end
    end

    simulate_platform "universal-java-16"

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"
      gem "platform_specific"
    G

    expected_checksums = checksum_section do |c|
      c.repo_gem gem_repo2, "platform_specific", "1.0", "universal-java-16"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          platform_specific (1.0-universal-java-16)

      PLATFORMS
        universal-java-16

      DEPENDENCIES
        platform_specific

      CHECKSUMS
        #{expected_checksums}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add duplicate gems" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"
      gem "rack"
    G

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"
      gem "rack"
      gem "activesupport"
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          activesupport (2.3.5)
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        activesupport
        rack

      CHECKSUMS
        #{checksum_for_repo_gem(gem_repo2, "activesupport", "2.3.5")}
        #{checksum_for_repo_gem(gem_repo2, "rack", "1.0.0")}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add duplicate dependencies" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"
      gem "rack"
      gem "rack"
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack

      CHECKSUMS
        #{checksum_for_repo_gem(gem_repo2, "rack", "1.0.0")}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add duplicate dependencies with versions" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"
      gem "rack", "1.0"
      gem "rack", "1.0"
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack (= 1.0)

      CHECKSUMS
        #{checksum_for_repo_gem(gem_repo2, "rack", "1.0.0")}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add duplicate dependencies in different groups" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"
      gem "rack", "1.0", :group => :one
      gem "rack", "1.0", :group => :two
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack (= 1.0)

      CHECKSUMS
        #{checksum_for_repo_gem(gem_repo2, "rack", "1.0.0")}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "raises if two different versions are used" do
    install_gemfile <<-G, :raise_on_error => false
      source "#{file_uri_for(gem_repo2)}/"
      gem "rack", "1.0"
      gem "rack", "1.1"
    G

    expect(bundled_app_lock).not_to exist
    expect(err).to include "rack (= 1.0) and rack (= 1.1)"
  end

  it "raises if two different sources are used" do
    install_gemfile <<-G, :raise_on_error => false
      source "#{file_uri_for(gem_repo2)}/"
      gem "rack"
      gem "rack", :git => "git://hubz.com"
    G

    expect(bundled_app_lock).not_to exist
    expect(err).to include "rack (>= 0) should come from an unspecified source and git://hubz.com"
  end

  it "works correctly with multiple version dependencies" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"
      gem "rack", "> 0.9", "< 1.0"
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (0.9.1)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack (> 0.9, < 1.0)

      CHECKSUMS
        #{checksum_for_repo_gem(gem_repo2, "rack", "0.9.1")}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "captures the Ruby version in the lockfile" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"
      ruby '#{Gem.ruby_version}'
      gem "rack", "> 0.9", "< 1.0"
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (0.9.1)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack (> 0.9, < 1.0)

      CHECKSUMS
        #{checksum_for_repo_gem(gem_repo2, "rack", "0.9.1")}

      RUBY VERSION
         #{Bundler::RubyVersion.system}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "raises a helpful error message when the lockfile is missing deps" do
    lockfile <<-L
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack_middleware (1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack_middleware
    L

    install_gemfile <<-G, :raise_on_error => false
      source "#{file_uri_for(gem_repo2)}"
      gem "rack_middleware"
    G

    expect(err).to include("Downloading rack_middleware-1.0 revealed dependencies not in the API or the lockfile (#{Gem::Dependency.new("rack", "= 0.9.1")}).").
      and include("Running `bundle update rack_middleware` should fix the problem.")
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
        remote: #{file_uri_for(gem_repo4)}/
        specs:

      PLATFORMS
        ruby

      DEPENDENCIES
        direct_dependency

      BUNDLED WITH
         #{Bundler::VERSION}
    G

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo4)}"

      gem "direct_dependency"
    G

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          direct_dependency (4.5.6)
            indirect_dependency
          indirect_dependency (1.2.3)

      PLATFORMS
        #{lockfile_platforms("ruby", generic_local_platform, :defaults => [])}

      DEPENDENCIES
        direct_dependency

      CHECKSUMS
        #{checksum_for_repo_gem(gem_repo4, "direct_dependency", "4.5.6")}
        #{checksum_for_repo_gem(gem_repo4, "indirect_dependency", "1.2.3")}

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
        source "#{file_uri_for(gem_repo4)}"
        gem "minitest-bisect"
      G

      # Corrupt lockfile (completely missing path_expander)
      lockfile <<~L
        GEM
          remote: #{file_uri_for(gem_repo4)}/
          specs:
            minitest-bisect (1.6.0)

        PLATFORMS
          #{platforms}

        DEPENDENCIES
          minitest-bisect

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      cache_gems "minitest-bisect-1.6.0", "path_expander-1.1.1", :gem_repo => gem_repo4
      bundle :install

      expect(lockfile).to eq <<~L
        GEM
          remote: #{file_uri_for(gem_repo4)}/
          specs:
            minitest-bisect (1.6.0)
              path_expander (~> 1.1)
            path_expander (1.1.1)

        PLATFORMS
          #{platforms}

        DEPENDENCIES
          minitest-bisect

        CHECKSUMS
          #{checksum_for_repo_gem(gem_repo4, "minitest-bisect", "1.6.0")}
          #{checksum_for_repo_gem(gem_repo4, "path_expander", "1.1.1")}

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
      source "#{file_uri_for(gem_repo4)}"
      gem "minitest-bisect"
    G

    lockfile <<~L
      GEM
        remote: #{file_uri_for(gem_repo4)}/
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
    expect(out).to include("re-resolving dependencies because your lock file is missing \"minitest-bisect\"")

    expect(lockfile).to eq <<~L
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          minitest-bisect (1.6.0)
            path_expander (~> 1.1)
          path_expander (1.1.1)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        minitest-bisect

      CHECKSUMS
        #{checksum_for_repo_gem gem_repo4, "minitest-bisect", "1.6.0"}
        #{checksum_for_repo_gem gem_repo4, "path_expander", "1.1.1"}

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
        source "#{file_uri_for(gem_repo2)}"
        gem "rack"
      G
      set_lockfile_mtime_to_known_value
    end

    it "generates Gemfile.lock with \\n line endings" do
      expect(File.read(bundled_app_lock)).not_to match("\r\n")
      expect(the_bundle).to include_gems "rack 1.0"
    end

    context "during updates" do
      it "preserves Gemfile.lock \\n line endings" do
        update_repo2 do
          build_gem "rack", "1.2" do |s|
            s.executables = "rackup"
          end
        end

        expect { bundle "update", :all => true }.to change { File.mtime(bundled_app_lock) }
        expect(File.read(bundled_app_lock)).not_to match("\r\n")
        expect(the_bundle).to include_gems "rack 1.2"
      end

      it "preserves Gemfile.lock \\n\\r line endings" do
        skip "needs to be adapted" if Gem.win_platform?

        update_repo2 do
          build_gem "rack", "1.2" do |s|
            s.executables = "rackup"
          end
        end

        win_lock = File.read(bundled_app_lock).gsub(/\n/, "\r\n")
        File.open(bundled_app_lock, "wb") {|f| f.puts(win_lock) }
        set_lockfile_mtime_to_known_value

        expect { bundle "update", :all => true }.to change { File.mtime(bundled_app_lock) }
        expect(File.read(bundled_app_lock)).to match("\r\n")

        simulate_bundler_version_when_missing_prerelease_default_gem_activation do
          expect(the_bundle).to include_gems "rack 1.2"
        end
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
                   require '#{entrypoint}'
                   Bundler.setup
                 RUBY
        end.not_to change { File.mtime(bundled_app_lock) }
      end
    end
  end

  it "refuses to install if Gemfile.lock contains conflict markers" do
    lockfile <<-L
      GEM
        remote: #{file_uri_for(gem_repo2)}//
        specs:
      <<<<<<<
          rack (1.0.0)
      =======
          rack (1.0.1)
      >>>>>>>

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    install_gemfile <<-G, :raise_on_error => false
      source "#{file_uri_for(gem_repo2)}/"
      gem "rack"
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
