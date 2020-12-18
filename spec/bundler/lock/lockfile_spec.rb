# frozen_string_literal: true

RSpec.describe "the lockfile format" do
  include Bundler::GemHelpers

  before do
    build_repo2 do
      # Capistrano did this (at least until version 2.5.10)
      # RubyGems 2.2 doesn't allow the specifying of a dependency twice
      # See https://github.com/rubygems/rubygems/commit/03dbac93a3396a80db258d9bc63500333c25bd2f
      build_gem "double_deps", "1.0", :skip_validation => true do |s|
        s.add_dependency "net-ssh", ">= 1.0.0"
        s.add_dependency "net-ssh"
      end
    end
  end

  it "generates a simple lockfile for a single source, gem" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"

      gem "rack"
    G

    lockfile_should_be <<-G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
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

    install_gemfile <<-G, :env => { "BUNDLER_VERSION" => Bundler::VERSION }
      source "#{file_uri_for(gem_repo2)}"

      gem "rack"
    G

    lockfile_should_be <<-G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
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

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"

      gem "rack"
    G

    lockfile_should_be <<-G
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

  it "updates the lockfile's bundler version if not present" do
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

    lockfile_should_be <<-G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
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

  it "warns if the current is older than lockfile's bundler version" do
    current_version = Bundler::VERSION
    newer_minor = bump_minor(current_version)

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
         #{newer_minor}
    L

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"

      gem "rack"
    G

    pre_flag = prerelease?(newer_minor) ? " --pre" : ""
    warning_message = "the running version of Bundler (#{current_version}) is older " \
                      "than the version that created the lockfile (#{newer_minor}). " \
                      "We suggest you to upgrade to the version that created the " \
                      "lockfile by running `gem install bundler:#{newer_minor}#{pre_flag}`."
    expect(err).to include warning_message

    lockfile_should_be <<-G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack

      BUNDLED WITH
         #{newer_minor}
    G
  end

  it "warns when updating bundler major version" do
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

    expect(err).to include(
      "Warning: the lockfile is being updated to Bundler " \
      "#{current_version.split(".").first}, after which you will be unable to return to Bundler #{older_major.split(".").first}."
    )

    lockfile_should_be <<-G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        rack

      BUNDLED WITH
         #{current_version}
    G
  end

  it "generates a simple lockfile for a single source, gem with dependencies" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"

      gem "rack-obama"
    G

    lockfile_should_be <<-G
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

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "generates a simple lockfile for a single source, gem with a version requirement" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"

      gem "rack-obama", ">= 1.0"
    G

    lockfile_should_be <<-G
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
      source "#{file_uri_for(gem_repo2)}/"
      gem "net-sftp"
    G

    lockfile_should_be <<-G
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

      BUNDLED WITH
         #{Bundler::VERSION}
    G

    expect(the_bundle).to include_gems "net-sftp 1.1.1", "net-ssh 1.0.0"
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

    install_gemfile <<-G
      gem "foo", :path => "#{lib_path("foo-1.0")}"
    G

    bundle "config set cache_all true"
    bundle :cache
    bundle :install, :local => true

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
      source "#{file_uri_for(gem_repo2)}/"

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
        remote: #{file_uri_for(gem_repo2)}/
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
      source "#{file_uri_for(gem_repo2)}/"

      gem "thin"
      gem "actionpack"
      gem "rack-obama"
    G

    lockfile_should_be <<-G
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

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "orders dependencies' dependencies in alphabetical order" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"

      gem "rails"
    G

    lockfile_should_be <<-G
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

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "orders dependencies by version" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"
      gem 'double_deps'
    G

    lockfile_should_be <<-G
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

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add the :require option to the lockfile" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"

      gem "rack-obama", ">= 1.0", :require => "rack/obama"
    G

    lockfile_should_be <<-G
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

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "does not add the :group option to the lockfile" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"

      gem "rack-obama", ">= 1.0", :group => :test
    G

    lockfile_should_be <<-G
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

    lockfile_should_be <<-G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          rack (1.0.0)

      PLATFORMS
        java
        #{lockfile_platforms}

      DEPENDENCIES
        rack

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

    lockfile_should_be <<-G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
        specs:
          platform_specific (1.0-universal-java-16)

      PLATFORMS
        universal-java-16

      DEPENDENCIES
        platform_specific

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

    lockfile_should_be <<-G
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

    lockfile_should_be <<-G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
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
      source "#{file_uri_for(gem_repo2)}/"
      gem "rack", "1.0"
      gem "rack", "1.0"
    G

    lockfile_should_be <<-G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
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
      source "#{file_uri_for(gem_repo2)}/"
      gem "rack", "1.0", :group => :one
      gem "rack", "1.0", :group => :two
    G

    lockfile_should_be <<-G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
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
    expect(err).to include "rack (>= 0) should come from an unspecified source and git://hubz.com (at master)"
  end

  it "works correctly with multiple version dependencies" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}/"
      gem "rack", "> 0.9", "< 1.0"
    G

    lockfile_should_be <<-G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
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
      source "#{file_uri_for(gem_repo2)}/"
      ruby '#{RUBY_VERSION}'
      gem "rack", "> 0.9", "< 1.0"
    G

    lockfile_should_be <<-G
      GEM
        remote: #{file_uri_for(gem_repo2)}/
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
      source "#{file_uri_for(gem_repo2)}/"
      gem "omg", :git => "#{lib_path("omg")}", :branch => 'master'
    G

    bundle "config --local path vendor"
    bundle :install
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
        remote: #{file_uri_for(gem_repo2)}/
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
        remote: #{file_uri_for(gem_repo2)}/
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
      and include("Either installing with `--full-index` or running `bundle update rack_middleware` should fix the problem.")
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
        expect(the_bundle).to include_gems "rack 1.2"
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
                   require '#{lib_dir}/bundler'
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
