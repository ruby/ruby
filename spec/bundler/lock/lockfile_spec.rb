# frozen_string_literal: true

RSpec.describe "the lockfile format" do
  include Bundler::GemHelpers

  before { ENV["BUNDLER_SPEC_IGNORE_COMPATIBILITY_GUARD"] = "TRUE" }

  it "generates a simple lockfile for a single source, gem" do
    install_gemfile <<-G
      source "file://localhost#{gem_repo1}"

      gem "rack"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "updates the lockfile's bundler version if current ver. is newer" do
    lockfile <<-L
      GIT
        remote: git://github.com/nex3/haml.git
        revision: 8a2271f
        specs:

      GEM
        remote: file://localhost#{gem_repo1}/
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

    install_gemfile <<-G
      source "file://localhost#{gem_repo1}"

      gem "rack"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not update the lockfile's bundler version if nothing changed during bundle install" do
    version = "#{Bundler::VERSION.split(".").first}.0.0.a"

    lockfile <<-L
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack

      BUNDLED WITH
         #{version}
    L

    install_gemfile <<-G
      source "file://localhost#{gem_repo1}"

      gem "rack"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
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

  it "updates the lockfile's bundler version if not present" do
    lockfile <<-L
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack
    L

    install_gemfile <<-G
      source "file://localhost#{gem_repo1}"

      gem "rack", "> 0"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack (> 0)

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "outputs a warning if the current is older than lockfile's bundler version" do
    lockfile <<-L
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{generic_local_platform}

      DEPENDENCIES
        rack

      BUNDLED WITH
         9999999.1.0
    L

    simulate_bundler_version "9999999.0.0" do
      install_gemfile <<-G
        source "file://localhost#{gem_repo1}"

        gem "rack"
      G
    end

    warning_message = "the running version of Bundler (9999999.0.0) is older " \
                      "than the version that created the lockfile (9999999.1.0). " \
                      "We suggest you to upgrade to the version that created the " \
                      "lockfile by running `gem install bundler:9999999.1.0`."
    expect(last_command.stderr).to include warning_message

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{generic_local_platform}
        #{specific_local_platform}

      DEPENDENCIES
        rack

      BUNDLED WITH
         9999999.1.0
    G
  end

  it "errors if the current is a major version older than lockfile's bundler version", :bundler => "3" do
    lockfile <<-L
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack

      BUNDLED WITH
         9999999.0.0
    L

    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"

      gem "rack"
    G

    expect(last_command).to be_failure
    expect(last_command.bundler_err).to include("You must use Bundler 9999999 or greater with this lockfile.")
  end

  it "shows a friendly error when running with a new bundler 2 lockfile" do
    lockfile <<-L
      GEM
        remote: https://rails-assets.org/
        specs:
         rails-assets-bootstrap (3.3.4)
           rails-assets-jquery (>= 1.9.1)
         rails-assets-jquery (2.1.4)

      GEM
        remote: https://rubygems.org/
        specs:
         rake (10.4.2)

      PLATFORMS
        ruby

      DEPENDENCIES
        rails-assets-bootstrap!
        rake

      BUNDLED WITH
         9999999.0.0
    L

    install_gemfile <<-G
      source 'https://rubygems.org'
      gem 'rake'

      source 'https://rails-assets.org' do
        gem 'rails-assets-bootstrap'
      end
    G

    expect(last_command).to be_failure
    expect(err).to include("You must use Bundler 9999999 or greater with this lockfile.")
  end

  it "warns when updating bundler major version", :bundler => "< 3" do
    lockfile <<-L
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{generic_local_platform}

      DEPENDENCIES
        rack

      BUNDLED WITH
         1.10.0
    L

    simulate_bundler_version "9999999.0.0" do
      install_gemfile <<-G
        source "file://localhost#{gem_repo1}/"

        gem "rack"
      G
    end

    expect(last_command.stderr).to include(
      "Warning: the lockfile is being updated to Bundler " \
      "9999999, after which you will be unable to return to Bundler 1."
    )

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{generic_local_platform}
        #{specific_local_platform}

      DEPENDENCIES
        rack

      BUNDLED WITH
         9999999.0.0
    G
  end

  it "warns when updating bundler major version", :bundler => "3" do
    lockfile <<-L
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack

      BUNDLED WITH
         1.10.0
    L

    simulate_bundler_version "9999999.0.0" do
      install_gemfile <<-G
        source "file://localhost#{gem_repo1}/"

        gem "rack"
      G

      expect(last_command.stderr).to include(
        "Warning: the lockfile is being updated to Bundler " \
        "9999999, after which you will be unable to return to Bundler 1."
      )

      lockfile_should_be <<-G
        GEM
          remote: file://localhost#{gem_repo1}/
          specs:
            rack (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          rack

        BUNDLED WITH
           9999999.0.0
      G
    end
  end

  it "generates a simple lockfile for a single source, gem with dependencies" do
    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"

      gem "rack-obama"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)
          rack-obama (1.0)
            rack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack-obama

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "generates a simple lockfile for a single source, gem with a version requirement" do
    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"

      gem "rack-obama", ">= 1.0"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)
          rack-obama (1.0)
            rack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack-obama (>= 1.0)

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "generates a lockfile without credentials for a configured source", :bundler => "< 3" do
    bundle "config set http://localgemserver.test/ user:pass"

    install_gemfile(<<-G, :artifice => "endpoint_strict_basic_authentication", :quiet => true)
      source "http://localgemserver.test/" do

      end

      source "http://user:pass@othergemserver.test/" do
        gem "rack-obama", ">= 1.0"
      end
    G

    lockfile_should_be <<-G
      GEM
        remote: http://localgemserver.test/
        remote: http://user:pass@othergemserver.test/
        specs:
          rack (1.0.0)
          rack-obama (1.0)
            rack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack-obama (>= 1.0)!

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "generates a lockfile without credentials for a configured source", :bundler => "3" do
    bundle "config set http://localgemserver.test/ user:pass"

    install_gemfile(<<-G, :artifice => "endpoint_strict_basic_authentication", :quiet => true)
      source "http://localgemserver.test/" do

      end

      source "http://user:pass@othergemserver.test/" do
        gem "rack-obama", ">= 1.0"
      end
    G

    lockfile_should_be <<-G
      GEM
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

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "generates lockfiles with multiple requirements" do
    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"
      gem "net-sftp"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          net-sftp (1.1.1)
            net-ssh (>= 1.0.0, < 1.99.0)
          net-ssh (1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        net-sftp

      BUNDLED WITH
         #{Bundler::VERSION}
    G

    expect(the_bundle).to include_gems "net-sftp 1.1.1", "net-ssh 1.0.0"
  end

  it "generates a simple lockfile for a single pinned source, gem with a version requirement", :bundler => "< 3" do
    git = build_git "foo"

    install_gemfile <<-G
      gem "foo", :git => "#{lib_path("foo-1.0")}"
    G

    lockfile_should_be <<-G
      GIT
        remote: #{lib_path("foo-1.0")}
        revision: #{git.ref_for("master")}
        specs:
          foo (1.0)

      GEM
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "generates a simple lockfile for a single pinned source, gem with a version requirement" do
    git = build_git "foo"

    install_gemfile <<-G
      gem "foo", :git => "#{lib_path("foo-1.0")}"
    G

    lockfile_should_be <<-G
      GIT
        remote: #{lib_path("foo-1.0")}
        revision: #{git.ref_for("master")}
        specs:
          foo (1.0)

      GEM
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not asplode when a platform specific dependency is present and the Gemfile has not been resolved on that platform" do
    build_lib "omg", :path => lib_path("omg")

    gemfile <<-G
      source "file://localhost#{gem_repo1}/"

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
        remote: file://localhost#{gem_repo1}//
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

    bundle! "install"
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "serializes global git sources" do
    git = build_git "foo"

    install_gemfile <<-G
      git "#{lib_path("foo-1.0")}" do
        gem "foo"
      end
    G

    lockfile_should_be <<-G
      GIT
        remote: #{lib_path("foo-1.0")}
        revision: #{git.ref_for("master")}
        specs:
          foo (1.0)

      GEM
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "generates a lockfile with a ref for a single pinned source, git gem with a branch requirement" do
    git = build_git "foo"
    update_git "foo", :branch => "omg"

    install_gemfile <<-G
      gem "foo", :git => "#{lib_path("foo-1.0")}", :branch => "omg"
    G

    lockfile_should_be <<-G
      GIT
        remote: #{lib_path("foo-1.0")}
        revision: #{git.ref_for("omg")}
        branch: omg
        specs:
          foo (1.0)

      GEM
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "generates a lockfile with a ref for a single pinned source, git gem with a tag requirement" do
    git = build_git "foo"
    update_git "foo", :tag => "omg"

    install_gemfile <<-G
      gem "foo", :git => "#{lib_path("foo-1.0")}", :tag => "omg"
    G

    lockfile_should_be <<-G
      GIT
        remote: #{lib_path("foo-1.0")}
        revision: #{git.ref_for("omg")}
        tag: omg
        specs:
          foo (1.0)

      GEM
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "serializes pinned path sources to the lockfile" do
    build_lib "foo"

    install_gemfile <<-G
      gem "foo", :path => "#{lib_path("foo-1.0")}"
    G

    lockfile_should_be <<-G
      PATH
        remote: #{lib_path("foo-1.0")}
        specs:
          foo (1.0)

      GEM
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "serializes pinned path sources to the lockfile even when packaging" do
    build_lib "foo"

    install_gemfile! <<-G
      gem "foo", :path => "#{lib_path("foo-1.0")}"
    G

    bundle! :package, forgotten_command_line_options([:all, :cache_all] => true)
    bundle! :install, :local => true

    lockfile_should_be <<-G
      PATH
        remote: #{lib_path("foo-1.0")}
        specs:
          foo (1.0)

      GEM
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "sorts serialized sources by type" do
    build_lib "foo"
    bar = build_git "bar"

    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"

      gem "rack"
      gem "foo", :path => "#{lib_path("foo-1.0")}"
      gem "bar", :git => "#{lib_path("bar-1.0")}"
    G

    lockfile_should_be <<-G
      GIT
        remote: #{lib_path("bar-1.0")}
        revision: #{bar.ref_for("master")}
        specs:
          bar (1.0)

      PATH
        remote: #{lib_path("foo-1.0")}
        specs:
          foo (1.0)

      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        bar!
        foo!
        rack

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "lists gems alphabetically" do
    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"

      gem "thin"
      gem "actionpack"
      gem "rack-obama"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
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

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "orders dependencies' dependencies in alphabetical order" do
    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"

      gem "rails"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
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
            rake (= 12.3.2)
          rake (12.3.2)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rails

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "orders dependencies by version" do
    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"
      gem 'double_deps'
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          double_deps (1.0)
            net-ssh
            net-ssh (>= 1.0.0)
          net-ssh (1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        double_deps

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add the :require option to the lockfile" do
    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"

      gem "rack-obama", ">= 1.0", :require => "rack/obama"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)
          rack-obama (1.0)
            rack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack-obama (>= 1.0)

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add the :group option to the lockfile" do
    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"

      gem "rack-obama", ">= 1.0", :group => :test
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)
          rack-obama (1.0)
            rack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack-obama (>= 1.0)

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "stores relative paths when the path is provided in a relative fashion and in Gemfile dir" do
    build_lib "foo", :path => bundled_app("foo")

    install_gemfile <<-G
      path "foo" do
        gem "foo"
      end
    G

    lockfile_should_be <<-G
      PATH
        remote: foo
        specs:
          foo (1.0)

      GEM
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "stores relative paths when the path is provided in a relative fashion and is above Gemfile dir" do
    build_lib "foo", :path => bundled_app(File.join("..", "foo"))

    install_gemfile <<-G
      path "../foo" do
        gem "foo"
      end
    G

    lockfile_should_be <<-G
      PATH
        remote: ../foo
        specs:
          foo (1.0)

      GEM
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "stores relative paths when the path is provided in an absolute fashion but is relative" do
    build_lib "foo", :path => bundled_app("foo")

    install_gemfile <<-G
      path File.expand_path("../foo", __FILE__) do
        gem "foo"
      end
    G

    lockfile_should_be <<-G
      PATH
        remote: foo
        specs:
          foo (1.0)

      GEM
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "stores relative paths when the path is provided for gemspec" do
    build_lib("foo", :path => tmp.join("foo"))

    install_gemfile <<-G
      gemspec :path => "../foo"
    G

    lockfile_should_be <<-G
      PATH
        remote: ../foo
        specs:
          foo (1.0)

      GEM
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "keeps existing platforms in the lockfile", :bundler => "< 3" do
    lockfile <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
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
      source "file://localhost#{gem_repo1}/"

      gem "rack"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)

      PLATFORMS
        java
        #{generic_local_platform}

      DEPENDENCIES
        rack

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "keeps existing platforms in the lockfile", :bundler => "3" do
    lockfile <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
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
      source "file://localhost#{gem_repo1}/"

      gem "rack"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)

      PLATFORMS
        java
        #{generic_local_platform}
        #{specific_local_platform}

      DEPENDENCIES
        rack

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "persists the spec's platform to the lockfile", :bundler => "< 3" do
    build_repo2 do
      build_gem "platform_specific", "1.0" do |s|
        s.platform = Gem::Platform.new("universal-java-16")
      end
    end

    simulate_platform "universal-java-16"

    install_gemfile! <<-G
      source "file://localhost#{gem_repo2}"
      gem "platform_specific"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo2}/
        specs:
          platform_specific (1.0-java)

      PLATFORMS
        java

      DEPENDENCIES
        platform_specific

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "persists the spec's platform and specific platform to the lockfile", :bundler => "3" do
    build_repo2 do
      build_gem "platform_specific", "1.0" do |s|
        s.platform = Gem::Platform.new("universal-java-16")
      end
    end

    simulate_platform "universal-java-16"

    install_gemfile! <<-G
      source "file://localhost#{gem_repo2}"
      gem "platform_specific"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo2}/
        specs:
          platform_specific (1.0-java)
          platform_specific (1.0-universal-java-16)

      PLATFORMS
        java
        universal-java-16

      DEPENDENCIES
        platform_specific

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add duplicate gems" do
    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"
      gem "rack"
    G

    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"
      gem "rack"
      gem "activesupport"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          activesupport (2.3.5)
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        activesupport
        rack

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add duplicate dependencies" do
    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"
      gem "rack"
      gem "rack"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add duplicate dependencies with versions" do
    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"
      gem "rack", "1.0"
      gem "rack", "1.0"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack (= 1.0)

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add duplicate dependencies in different groups" do
    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"
      gem "rack", "1.0", :group => :one
      gem "rack", "1.0", :group => :two
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack (= 1.0)

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "raises if two different versions are used" do
    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"
      gem "rack", "1.0"
      gem "rack", "1.1"
    G

    expect(bundled_app("Gemfile.lock")).not_to exist
    expect(err).to include "rack (= 1.0) and rack (= 1.1)"
  end

  it "raises if two different sources are used" do
    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"
      gem "rack"
      gem "rack", :git => "git://hubz.com"
    G

    expect(bundled_app("Gemfile.lock")).not_to exist
    expect(err).to include "rack (>= 0) should come from an unspecified source and git://hubz.com (at master)"
  end

  it "works correctly with multiple version dependencies" do
    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"
      gem "rack", "> 0.9", "< 1.0"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (0.9.1)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack (> 0.9, < 1.0)

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "captures the Ruby version in the lockfile" do
    install_gemfile <<-G
      source "file://localhost#{gem_repo1}/"
      ruby '#{RUBY_VERSION}'
      gem "rack", "> 0.9", "< 1.0"
    G

    lockfile_should_be <<-G
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack (0.9.1)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack (> 0.9, < 1.0)

      RUBY VERSION
         ruby #{RUBY_VERSION}p#{RUBY_PATCHLEVEL}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  # Some versions of the Bundler 1.1 RC series introduced corrupted
  # lockfiles. There were two major problems:
  #
  # * multiple copies of the same GIT section appeared in the lockfile
  # * when this happened, those sections got multiple copies of gems
  #   in those sections.
  it "fixes corrupted lockfiles" do
    build_git "omg", :path => lib_path("omg")
    revision = revision_for(lib_path("omg"))

    gemfile <<-G
      source "file://localhost#{gem_repo1}/"
      gem "omg", :git => "#{lib_path("omg")}", :branch => 'master'
    G

    bundle! :install, forgotten_command_line_options(:path => "vendor")
    expect(the_bundle).to include_gems "omg 1.0"

    # Create a Gemfile.lock that has duplicate GIT sections
    lockfile <<-L
      GIT
        remote: #{lib_path("omg")}
        revision: #{revision}
        branch: master
        specs:
          omg (1.0)

      GIT
        remote: #{lib_path("omg")}
        revision: #{revision}
        branch: master
        specs:
          omg (1.0)

      GEM
        remote: file://localhost#{gem_repo1}/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        omg!

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    FileUtils.rm_rf(bundled_app("vendor"))
    bundle "install"
    expect(the_bundle).to include_gems "omg 1.0"

    # Confirm that duplicate specs do not appear
    lockfile_should_be(<<-L)
      GIT
        remote: #{lib_path("omg")}
        revision: #{revision}
        branch: master
        specs:
          omg (1.0)

      GEM
        remote: file://localhost#{gem_repo1}/
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        omg!

      BUNDLED WITH
         #{Bundler::VERSION}
    L
  end

  it "raises a helpful error message when the lockfile is missing deps" do
    lockfile <<-L
      GEM
        remote: file://localhost#{gem_repo1}/
        specs:
          rack_middleware (1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack_middleware
    L

    install_gemfile <<-G
      source "file://localhost#{gem_repo1}"
      gem "rack_middleware"
    G

    expect(err).to include("Downloading rack_middleware-1.0 revealed dependencies not in the API or the lockfile (#{Gem::Dependency.new("rack", "= 0.9.1")}).").
      and include("Either installing with `--full-index` or running `bundle update rack_middleware` should fix the problem.")
  end

  describe "a line ending" do
    def set_lockfile_mtime_to_known_value
      time = Time.local(2000, 1, 1, 0, 0, 0)
      File.utime(time, time, bundled_app("Gemfile.lock"))
    end
    before(:each) do
      build_repo2

      install_gemfile <<-G
        source "file://localhost#{gem_repo2}"
        gem "rack"
      G
      set_lockfile_mtime_to_known_value
    end

    it "generates Gemfile.lock with \\n line endings" do
      expect(File.read(bundled_app("Gemfile.lock"))).not_to match("\r\n")
      expect(the_bundle).to include_gems "rack 1.0"
    end

    context "during updates" do
      it "preserves Gemfile.lock \\n line endings" do
        update_repo2

        expect { bundle "update", :all => true }.to change { File.mtime(bundled_app("Gemfile.lock")) }
        expect(File.read(bundled_app("Gemfile.lock"))).not_to match("\r\n")
        expect(the_bundle).to include_gems "rack 1.2"
      end

      it "preserves Gemfile.lock \\n\\r line endings" do
        update_repo2
        win_lock = File.read(bundled_app("Gemfile.lock")).gsub(/\n/, "\r\n")
        File.open(bundled_app("Gemfile.lock"), "wb") {|f| f.puts(win_lock) }
        set_lockfile_mtime_to_known_value

        expect { bundle "update", :all => true }.to change { File.mtime(bundled_app("Gemfile.lock")) }
        expect(File.read(bundled_app("Gemfile.lock"))).to match("\r\n")
        expect(the_bundle).to include_gems "rack 1.2"
      end
    end

    context "when nothing changes" do
      it "preserves Gemfile.lock \\n line endings" do
        expect do
          ruby <<-RUBY
                   require 'rubygems'
                   require 'bundler'
                   Bundler.setup
                 RUBY
        end.not_to change { File.mtime(bundled_app("Gemfile.lock")) }
      end

      it "preserves Gemfile.lock \\n\\r line endings" do
        win_lock = File.read(bundled_app("Gemfile.lock")).gsub(/\n/, "\r\n")
        File.open(bundled_app("Gemfile.lock"), "wb") {|f| f.puts(win_lock) }
        set_lockfile_mtime_to_known_value

        expect do
          ruby <<-RUBY
                   require 'rubygems'
                   require 'bundler'
                   Bundler.setup
                 RUBY
        end.not_to change { File.mtime(bundled_app("Gemfile.lock")) }
      end
    end
  end

  it "refuses to install if Gemfile.lock contains conflict markers" do
    lockfile <<-L
      GEM
        remote: file://localhost#{gem_repo1}//
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

    install_gemfile(<<-G)
      source "file://localhost#{gem_repo1}/"
      gem "rack"
    G

    expect(last_command.bundler_err).to match(/your Gemfile.lock contains merge conflicts/i)
    expect(last_command.bundler_err).to match(/git checkout HEAD -- Gemfile.lock/i)
  end
end
