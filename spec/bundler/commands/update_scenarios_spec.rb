# frozen_string_literal: true

RSpec.describe "bundle update in more complicated situations" do
  before do
    build_repo2
  end

  it "will eagerly unlock dependencies of a specified gem" do
    install_gemfile <<-G
      source "https://gem.repo2"

      gem "thin"
      gem "myrack-obama"
    G

    update_repo2 do
      build_gem "myrack", "1.2" do |s|
        s.executables = "myrackup"
      end

      build_gem "thin", "2.0" do |s|
        s.add_dependency "myrack"
      end
    end

    bundle "update thin"
    expect(the_bundle).to include_gems "thin 2.0", "myrack 1.2", "myrack-obama 1.0"
  end

  it "will warn when some explicitly updated gems are not updated" do
    install_gemfile <<-G
      source "https://gem.repo2"

      gem "thin"
      gem "myrack-obama"
    G

    update_repo2 do
      build_gem("thin", "2.0") {|s| s.add_dependency "myrack" }
      build_gem "myrack", "10.0"
    end

    bundle "update thin myrack-obama"
    expect(stdboth).to include "Bundler attempted to update myrack-obama but its version stayed the same"
    expect(the_bundle).to include_gems "thin 2.0", "myrack 10.0", "myrack-obama 1.0"
  end

  it "will not warn when an explicitly updated git gem changes sha but not version" do
    build_git "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G

    update_git "foo" do |s|
      s.write "lib/foo2.rb", "puts :foo2"
    end

    bundle "update foo"

    expect(stdboth).not_to include "attempted to update"
  end

  it "will not warn when changing gem sources but not versions" do
    build_git "myrack"

    install_gemfile <<-G
      source "https://gem.repo2"
      gem "myrack", :git => '#{lib_path("myrack-1.0")}'
    G

    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G

    bundle "update myrack"

    expect(stdboth).not_to include "attempted to update"
  end

  it "will update only from pinned source" do
    install_gemfile <<-G
      source "https://gem.repo2"

      source "https://gem.repo1" do
        gem "thin"
      end
    G

    update_repo2 do
      build_gem "thin", "2.0"
    end

    bundle "update", artifice: "compact_index"
    expect(the_bundle).to include_gems "thin 1.0"
  end

  context "when the lockfile is for a different platform" do
    around do |example|
      build_repo4 do
        build_gem("a", "0.9")
        build_gem("a", "0.9") {|s| s.platform = "java" }
        build_gem("a", "1.1")
        build_gem("a", "1.1") {|s| s.platform = "java" }
      end

      gemfile <<-G
        source "https://gem.repo4"
        gem "a"
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo4
          specs:
            a (0.9-java)

        PLATFORMS
          java

        DEPENDENCIES
          a
      L

      simulate_platform "x86_64-linux", &example
    end

    it "allows updating" do
      bundle :update, all: true
      expect(the_bundle).to include_gem "a 1.1"
    end

    it "allows updating a specific gem" do
      bundle "update a"
      expect(the_bundle).to include_gem "a 1.1"
    end
  end

  context "when the dependency is for a different platform" do
    before do
      build_repo4 do
        build_gem("a", "0.9") {|s| s.platform = "java" }
        build_gem("a", "1.1") {|s| s.platform = "java" }
      end

      gemfile <<-G
        source "https://gem.repo4"
        gem "a", platform: :jruby
      G

      lockfile <<-L
        GEM
          remote: https://gem.repo4
          specs:
            a (0.9-java)

        PLATFORMS
          java

        DEPENDENCIES
          a
      L
    end

    it "is not updated because it is not actually included in the bundle" do
      simulate_platform "x86_64-linux" do
        bundle "update a"
        expect(stdboth).to include "Bundler attempted to update a but it was not considered because it is for a different platform from the current one"
        expect(the_bundle).to_not include_gem "a"
      end
    end
  end
end

RSpec.describe "bundle update without a Gemfile.lock" do
  it "should not explode" do
    build_repo2

    gemfile <<-G
      source "https://gem.repo2"

      gem "myrack", "1.0"
    G

    bundle "update", all: true

    expect(the_bundle).to include_gems "myrack 1.0.0"
  end
end

RSpec.describe "bundle update when a gem depends on a newer version of bundler" do
  before do
    build_repo2 do
      build_gem "rails", "3.0.1" do |s|
        s.add_dependency "bundler", "9.9.9"
      end

      build_gem "bundler", "9.9.9"
    end

    gemfile <<-G
      source "https://gem.repo2"
      gem "rails", "3.0.1"
    G
  end

  it "should explain that bundler conflicted and how to resolve the conflict" do
    bundle "update", all: true, raise_on_error: false
    expect(stdboth).not_to match(/in snapshot/i)
    expect(err).to match(/current Bundler version/i).
      and match(/Install the necessary version with `gem install bundler:9\.9\.9`/i)
  end
end

RSpec.describe "bundle update --ruby" do
  context "when the Gemfile removes the ruby" do
    before do
      install_gemfile <<-G
        ruby '~> #{Gem.ruby_version}'
        source "https://gem.repo1"
      G

      gemfile <<-G
        source "https://gem.repo1"
      G
    end

    it "removes the Ruby from the Gemfile.lock" do
      bundle "update --ruby"

      expect(lockfile).to eq <<~L
       GEM
         remote: https://gem.repo1/
         specs:

       PLATFORMS
         #{lockfile_platforms}

       DEPENDENCIES
       #{checksums_section_when_enabled}
       BUNDLED WITH
         #{Bundler::VERSION}
      L
    end
  end

  context "when the Gemfile specified an updated Ruby version" do
    before do
      install_gemfile <<-G
        ruby '~> #{Gem.ruby_version}'
        source "https://gem.repo1"
      G

      gemfile <<-G
        ruby '~> #{current_ruby_minor}'
        source "https://gem.repo1"
      G
    end

    it "updates the Gemfile.lock with the latest version" do
      bundle "update --ruby"

      expect(lockfile).to eq <<~L
        GEM
          remote: https://gem.repo1/
          specs:

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
        #{checksums_section_when_enabled}
        RUBY VERSION
          #{Bundler::RubyVersion.system}

        BUNDLED WITH
          #{Bundler::VERSION}
      L
    end
  end

  context "when a different Ruby is being used than has been versioned" do
    before do
      install_gemfile <<-G
        ruby '~> #{Gem.ruby_version}'
        source "https://gem.repo1"
      G

      gemfile <<-G
          ruby '~> 2.1.0'
          source "https://gem.repo1"
      G
    end
    it "shows a helpful error message" do
      bundle "update --ruby", raise_on_error: false

      expect(err).to include("Your Ruby version is #{Bundler::RubyVersion.system.gem_version}, but your Gemfile specified ~> 2.1.0")
    end
  end

  context "when updating Ruby version and Gemfile `ruby`" do
    before do
      lockfile <<~L
       GEM
         remote: https://gem.repo1/
         specs:

       PLATFORMS
         #{lockfile_platforms}

       DEPENDENCIES

       CHECKSUMS

       RUBY VERSION
          ruby 2.1.4p222

       BUNDLED WITH
         #{Bundler::VERSION}
      L

      gemfile <<-G
          ruby '~> #{Gem.ruby_version}'
          source "https://gem.repo1"
      G
    end

    it "updates the Gemfile.lock with the latest version" do
      bundle "update --ruby"

      expect(lockfile).to eq <<~L
       GEM
         remote: https://gem.repo1/
         specs:

       PLATFORMS
         #{lockfile_platforms}

       DEPENDENCIES
       #{checksums_section_when_enabled}
       RUBY VERSION
         #{Bundler::RubyVersion.system}

       BUNDLED WITH
         #{Bundler::VERSION}
      L
    end
  end
end

RSpec.describe "bundle update --bundler" do
  it "updates the bundler version in the lockfile" do
    build_repo4 do
      build_gem "bundler", "2.5.9"
      build_gem "myrack", "1.0"
    end

    checksums = checksums_section_when_enabled do |c|
      c.checksum(gem_repo4, "myrack", "1.0")
    end

    install_gemfile <<-G
      source "https://gem.repo4"
      gem "myrack"
    G
    expect(lockfile).to eq <<~L
      GEM
        remote: https://gem.repo4/
        specs:
          myrack (1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack
      #{checksums}
      BUNDLED WITH
        #{Bundler::VERSION}
    L
    lockfile lockfile.sub(/(^\s*)#{Bundler::VERSION}($)/, '\11.0.0\2')

    bundle :update, bundler: true, verbose: true
    expect(out).to include("Using bundler #{Bundler::VERSION}")

    expect(lockfile).to eq <<~L
      GEM
        remote: https://gem.repo4/
        specs:
          myrack (1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack
      #{checksums}
      BUNDLED WITH
        #{Bundler::VERSION}
    L

    expect(the_bundle).to include_gem "myrack 1.0"
  end

  it "updates the bundler version in the lockfile without re-resolving if the highest version is already installed" do
    build_repo4 do
      build_gem "bundler", "2.3.9"
      build_gem "myrack", "1.0"
    end

    install_gemfile <<-G
      source "https://gem.repo4"
      gem "myrack"
    G
    lockfile lockfile.sub(/(^\s*)#{Bundler::VERSION}($)/, "2.3.9")

    checksums = checksums_section_when_enabled do |c|
      c.checksum(gem_repo4, "myrack", "1.0")
    end

    bundle :update, bundler: true, verbose: true
    expect(out).to include("Using bundler #{Bundler::VERSION}")

    expect(lockfile).to eq <<~L
      GEM
        remote: https://gem.repo4/
        specs:
          myrack (1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack
      #{checksums}
      BUNDLED WITH
        #{Bundler::VERSION}
    L

    expect(the_bundle).to include_gem "myrack 1.0"
  end

  it "updates the bundler version in the lockfile even if the latest version is not installed", :ruby_repo do
    bundle_config "path.system true"

    pristine_system_gems "bundler-9.0.0"

    build_repo4 do
      build_gem "myrack", "1.0"

      build_bundler "999.0.0"
    end

    checksums = checksums_section do |c|
      c.checksum(gem_repo4, "myrack", "1.0")
      c.checksum(gem_repo4, "bundler", "999.0.0")
    end

    install_gemfile <<-G
      source "https://gem.repo4"
      gem "myrack"
    G

    bundle :update, bundler: true, verbose: true

    expect(out).to include("Updating bundler to 999.0.0")
    expect(out).to include("Running `bundle update --bundler \"> 0.a\" --verbose` with bundler 999.0.0")
    expect(out).not_to include("Installing Bundler 2.99.9 and restarting using that version.")

    expect(lockfile).to eq <<~L
      GEM
        remote: https://gem.repo4/
        specs:
          myrack (1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack
      #{checksums}
      BUNDLED WITH
        999.0.0
    L

    bundle "--version"
    expect(out).to include("999.0.0")

    bundle "list"
    expect(out).to include("myrack (1.0)")
  end

  it "does not claim to update to Bundler version to a wrong version when cached gems are present" do
    pristine_system_gems "bundler-4.99.0"

    build_repo4 do
      build_gem "myrack", "3.0.9.1"

      build_bundler "4.99.0"
    end

    gemfile <<~G
      source "https://gem.repo4"
      gem "myrack"
    G

    lockfile <<~L
      GEM
        remote: https://gem.repo4/
        specs:
          myrack (3.0.9.1)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
       myrack

      BUNDLED WITH
         2.99.0
    L

    bundle :cache, verbose: true

    bundle :update, bundler: true, verbose: true

    expect(out).not_to include("Updating bundler to")
  end

  it "does not update the bundler version in the lockfile if the latest version is not compatible with current ruby", :ruby_repo do
    pristine_system_gems "bundler-9.9.9"

    build_repo4 do
      build_gem "myrack", "1.0"

      build_bundler "9.9.9"
      build_bundler "999.0.0" do |s|
        s.required_ruby_version = "> #{Gem.ruby_version}"
      end
    end

    checksums = checksums_section do |c|
      c.checksum(gem_repo4, "myrack", "1.0")
      c.checksum(gem_repo4, "bundler", "9.9.9")
    end

    install_gemfile <<-G
      source "https://gem.repo4"
      gem "myrack"
    G

    bundle :update, bundler: true, verbose: true

    expect(out).to include("Using bundler 9.9.9")

    expect(lockfile).to eq <<~L
      GEM
        remote: https://gem.repo4/
        specs:
          myrack (1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack
      #{checksums}
      BUNDLED WITH
        9.9.9
    L

    bundle "--version"
    expect(out).to include("9.9.9")

    bundle "list"
    expect(out).to include("myrack (1.0)")
  end

  it "errors if the explicit target version does not exist" do
    pristine_system_gems "bundler-9.9.9"

    build_repo4 do
      build_gem "myrack", "1.0"
    end

    install_gemfile <<-G
      source "https://gem.repo4"
      gem "myrack"
    G

    bundle :update, bundler: "999.999.999", raise_on_error: false

    expect(last_command).to be_failure
    expect(err).to eq("The `bundle update --bundler` target version (999.999.999) does not exist")
  end

  it "errors if the explicit target version does not exist, even if auto switching is disabled" do
    pristine_system_gems "bundler-9.9.9"

    build_repo4 do
      build_gem "myrack", "1.0"
    end

    install_gemfile <<-G
      source "https://gem.repo4"
      gem "myrack"
    G

    bundle :update, bundler: "999.999.999", raise_on_error: false, env: { "BUNDLER_VERSION" => "9.9.9" }

    expect(last_command).to be_failure
    expect(err).to eq("The `bundle update --bundler` target version (999.999.999) does not exist")
  end

  it "allows updating to development versions if already installed locally" do
    system_gems "bundler-9.9.9"

    build_repo4 do
      build_gem "myrack", "1.0"
    end

    install_gemfile <<-G
      source "https://gem.repo4"
      gem "myrack"
    G

    system_gems "bundler-9.0.0.dev", path: local_gem_path
    bundle :update, bundler: "9.0.0.dev", verbose: "true"

    checksums = checksums_section_when_enabled do |c|
      c.checksum(gem_repo4, "myrack", "1.0")
    end
    checksums.delete("bundler")

    expect(lockfile).to eq <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            myrack (1.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          myrack
        #{checksums}
        BUNDLED WITH
          9.0.0.dev
      L

    expect(out).to include("Using bundler 9.0.0.dev")
  end

  it "does not touch the network if not necessary" do
    system_gems "bundler-9.9.9"

    build_repo4 do
      build_gem "myrack", "1.0"
    end

    install_gemfile <<-G
      source "https://gem.repo4"
      gem "myrack"
    G
    system_gems "bundler-9.0.0", path: local_gem_path
    bundle :update, bundler: "9.0.0", verbose: true

    expect(out).not_to include("Fetching gem metadata from https://rubygems.org/")

    # Only updates properly on modern RubyGems.
    checksums = checksums_section_when_enabled do |c|
      c.checksum(gem_repo4, "myrack", "1.0")
      c.checksum(local_gem_path, "bundler", "9.0.0", Gem::Platform::RUBY, "cache")
    end

    expect(lockfile).to eq <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            myrack (1.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          myrack
        #{checksums}
        BUNDLED WITH
          9.0.0
      L

    expect(out).to include("Using bundler 9.0.0")
  end

  it "preserves the locked bundler checksum when re-locking without the bundler gem cached" do
    system_gems "bundler-9.0.0"

    build_repo4 do
      build_gem "myrack", "1.0"
      build_gem "weakling", "0.0.3"

      build_bundler "9.0.0"
    end

    install_gemfile <<-G
      source "https://gem.repo4"
      gem "myrack"
    G

    system_gems "bundler-9.0.0", path: local_gem_path
    bundle :update, bundler: "9.0.0", verbose: true

    # Sanity check: the lockfile now records the bundler checksum.
    expect(lockfile).to match(/^  bundler \(9\.0\.0\) sha256=/)

    # Simulate a machine where the bundler gem is not present in the cache
    # (e.g. a fresh CI checkout that never downloaded bundler-9.0.0.gem).
    FileUtils.rm_f Dir[local_gem_path("cache", "bundler-9.0.0.gem")]
    FileUtils.rm_f Dir[system_gem_path("cache", "bundler-9.0.0.gem")]

    # Force a re-resolution / lockfile rewrite.
    install_gemfile <<-G
      source "https://gem.repo4"
      gem "myrack"
      gem "weakling"
    G

    # The bundler checksum must survive the rewrite, since it was already locked.
    expect(lockfile).to match(/^  bundler \(9\.0\.0\) sha256=/)
  end

  it "drops the locked bundler checksum when the bundler version changes and the gem isn't cached" do
    system_gems "bundler-9.0.0"

    build_repo4 do
      build_gem "myrack", "1.0"

      build_bundler "9.0.0"
      build_bundler "9.9.9"
    end

    install_gemfile <<-G
      source "https://gem.repo4"
      gem "myrack"
    G

    system_gems "bundler-9.0.0", path: local_gem_path
    bundle :update, bundler: "9.0.0", verbose: true

    # Sanity check: the lockfile records the bundler 9.0.0 checksum and is
    # locked to bundler 9.0.0.
    expect(lockfile).to match(/^  bundler \(9\.0\.0\) sha256=/)
    expect(lockfile).to match(/BUNDLED WITH\n\s+9\.0\.0\n/)

    # Simulate a machine where the bundler gem is not present in the cache
    # (e.g. a fresh CI checkout), so a fresh checksum can't be computed.
    FileUtils.rm_f Dir[local_gem_path("cache", "bundler-9.0.0.gem")]
    FileUtils.rm_f Dir[system_gem_path("cache", "bundler-9.0.0.gem")]

    # Change the locked bundler version. `bundle lock --update --bundler` rewrites
    # the BUNDLED WITH section without switching the running bundler, so the gem
    # whose checksum is locked (9.0.0) is no longer the version being locked.
    bundle "lock --update --bundler 9.9.9", verbose: true

    # The BUNDLED WITH version was bumped...
    expect(lockfile).to match(/BUNDLED WITH\n\s+9\.9\.9\n/)

    # ...so the stale `bundler (9.0.0)` checksum must be dropped rather than kept,
    # otherwise we'd lock a checksum that no longer matches the BUNDLED WITH
    # version (and that we can't recompute since the gem isn't cached).
    expect(lockfile).not_to match(/^  bundler \(/)
  end

  it "prints an error when trying to update bundler in frozen mode" do
    system_gems "bundler-9.0.0"

    gemfile <<~G
      source "https://gem.repo2"
    G

    lockfile <<-L
      GEM
        remote: https://gem.repo2/
        specs:

      PLATFORMS
        ruby

      DEPENDENCIES

      BUNDLED WITH
         9.0.0
    L

    system_gems "bundler-9.9.9", path: local_gem_path

    bundle "update --bundler=9.9.9", env: { "BUNDLE_FROZEN" => "true" }, raise_on_error: false
    expect(err).to include("An update to the version of Bundler itself was requested, but the lockfile can't be updated because frozen mode is set")
  end
end

# these specs are slow and focus on integration and therefore are not exhaustive. unit specs elsewhere handle that.
RSpec.describe "bundle update conservative" do
  context "patch and minor options" do
    before do
      build_repo4 do
        build_gem "foo", %w[1.4.3 1.4.4] do |s|
          s.add_dependency "bar", "~> 2.0"
        end
        build_gem "foo", %w[1.4.5 1.5.0] do |s|
          s.add_dependency "bar", "~> 2.1"
        end
        build_gem "foo", %w[1.5.1] do |s|
          s.add_dependency "bar", "~> 3.0"
        end
        build_gem "foo", %w[2.0.0.pre] do |s|
          s.add_dependency "bar"
        end
        build_gem "bar", %w[2.0.3 2.0.4 2.0.5 2.1.0 2.1.1 2.1.2.pre 3.0.0 3.1.0.pre 4.0.0.pre]
        build_gem "qux", %w[1.0.0 1.0.1 1.1.0 2.0.0]
      end

      # establish a lockfile set to 1.4.3
      install_gemfile <<-G
        source "https://gem.repo4"
        gem 'foo', '1.4.3'
        gem 'bar', '2.0.3'
        gem 'qux', '1.0.0'
      G

      # remove 1.4.3 requirement and bar altogether
      # to setup update specs below
      gemfile <<-G
        source "https://gem.repo4"
        gem 'foo'
        gem 'qux'
      G
    end

    context "with patch set as default update level in config" do
      it "should do a patch level update" do
        bundle_config "prefer_patch true"
        bundle "update foo"

        expect(the_bundle).to include_gems "foo 1.4.5", "bar 2.1.1", "qux 1.0.0"
      end
    end

    context "patch preferred" do
      it "single gem updates dependent gem to minor" do
        bundle "update --patch foo"

        expect(the_bundle).to include_gems "foo 1.4.5", "bar 2.1.1", "qux 1.0.0"
      end

      it "update all" do
        bundle "update --patch", all: true

        expect(the_bundle).to include_gems "foo 1.4.5", "bar 2.1.1", "qux 1.0.1"
      end
    end

    context "minor preferred" do
      it "single gem updates dependent gem to major" do
        bundle "update --minor foo"

        expect(the_bundle).to include_gems "foo 1.5.1", "bar 3.0.0", "qux 1.0.0"
      end
    end

    context "strict" do
      it "patch preferred" do
        bundle "update --patch foo bar --strict"

        expect(the_bundle).to include_gems "foo 1.4.4", "bar 2.0.5", "qux 1.0.0"
      end

      it "minor preferred" do
        bundle "update --minor --strict", all: true

        expect(the_bundle).to include_gems "foo 1.5.0", "bar 2.1.1", "qux 1.1.0"
      end
    end

    context "pre" do
      it "defaults to major" do
        bundle "update --pre foo bar"

        expect(the_bundle).to include_gems "foo 2.0.0.pre", "bar 4.0.0.pre", "qux 1.0.0"
      end

      it "patch preferred" do
        bundle "update --patch --pre foo bar"

        expect(the_bundle).to include_gems "foo 1.4.5", "bar 2.1.2.pre", "qux 1.0.0"
      end

      it "minor preferred" do
        bundle "update --minor --pre foo bar"

        expect(the_bundle).to include_gems "foo 1.5.1", "bar 3.1.0.pre", "qux 1.0.0"
      end

      it "major preferred" do
        bundle "update --major --pre foo bar"

        expect(the_bundle).to include_gems "foo 2.0.0.pre", "bar 4.0.0.pre", "qux 1.0.0"
      end
    end
  end

  context "eager unlocking" do
    before do
      build_repo4 do
        build_gem "isolated_owner", %w[1.0.1 1.0.2] do |s|
          s.add_dependency "isolated_dep", "~> 2.0"
        end
        build_gem "isolated_dep", %w[2.0.1 2.0.2]

        build_gem "shared_owner_a", %w[3.0.1 3.0.2] do |s|
          s.add_dependency "shared_dep", "~> 5.0"
        end
        build_gem "shared_owner_b", %w[4.0.1 4.0.2] do |s|
          s.add_dependency "shared_dep", "~> 5.0"
        end
        build_gem "shared_dep", %w[5.0.1 5.0.2]
      end

      gemfile <<-G
        source "https://gem.repo4"
        gem 'isolated_owner'

        gem 'shared_owner_a'
        gem 'shared_owner_b'
      G

      lockfile <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            isolated_dep (2.0.1)
            isolated_owner (1.0.1)
              isolated_dep (~> 2.0)
            shared_dep (5.0.1)
            shared_owner_a (3.0.1)
              shared_dep (~> 5.0)
            shared_owner_b (4.0.1)
              shared_dep (~> 5.0)

        PLATFORMS
          #{local_platform}

        DEPENDENCIES
          isolated_owner
          shared_owner_a
          shared_owner_b

        CHECKSUMS

        BUNDLED WITH
          #{Bundler::VERSION}
      L
    end

    it "should eagerly unlock isolated dependency" do
      bundle "update isolated_owner"

      expect(the_bundle).to include_gems "isolated_owner 1.0.2", "isolated_dep 2.0.2", "shared_dep 5.0.1", "shared_owner_a 3.0.1", "shared_owner_b 4.0.1"
    end

    it "should eagerly unlock shared dependency" do
      bundle "update shared_owner_a"

      expect(the_bundle).to include_gems "isolated_owner 1.0.1", "isolated_dep 2.0.1", "shared_dep 5.0.2", "shared_owner_a 3.0.2", "shared_owner_b 4.0.1"
    end

    it "should not eagerly unlock with --conservative" do
      bundle "update --conservative shared_owner_a isolated_owner"

      expect(the_bundle).to include_gems "isolated_owner 1.0.2", "isolated_dep 2.0.1", "shared_dep 5.0.1", "shared_owner_a 3.0.2", "shared_owner_b 4.0.1"
    end

    it "should only update direct dependencies when fully updating with --conservative" do
      bundle "update --conservative"

      expect(the_bundle).to include_gems "isolated_owner 1.0.2", "isolated_dep 2.0.1", "shared_dep 5.0.1", "shared_owner_a 3.0.2", "shared_owner_b 4.0.2"
    end

    it "should only change direct dependencies when updating the lockfile with --conservative" do
      bundle "lock --update --conservative"

      checksums = checksums_section_when_enabled do |c|
        c.checksum gem_repo4, "isolated_dep", "2.0.1"
        c.checksum gem_repo4, "isolated_owner", "1.0.2"
        c.checksum gem_repo4, "shared_dep", "5.0.1"
        c.checksum gem_repo4, "shared_owner_a", "3.0.2"
        c.checksum gem_repo4, "shared_owner_b", "4.0.2"
      end

      expect(lockfile).to eq <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            isolated_dep (2.0.1)
            isolated_owner (1.0.2)
              isolated_dep (~> 2.0)
            shared_dep (5.0.1)
            shared_owner_a (3.0.2)
              shared_dep (~> 5.0)
            shared_owner_b (4.0.2)
              shared_dep (~> 5.0)

        PLATFORMS
          #{local_platform}

        DEPENDENCIES
          isolated_owner
          shared_owner_a
          shared_owner_b
        #{checksums}
        BUNDLED WITH
          #{Bundler::VERSION}
      L
    end

    it "should match bundle install conservative update behavior when not eagerly unlocking" do
      gemfile <<-G
        source "https://gem.repo4"
        gem 'isolated_owner', '1.0.2'

        gem 'shared_owner_a', '3.0.2'
        gem 'shared_owner_b'
      G

      bundle "install"

      expect(the_bundle).to include_gems "isolated_owner 1.0.2", "isolated_dep 2.0.1", "shared_dep 5.0.1", "shared_owner_a 3.0.2", "shared_owner_b 4.0.1"
    end
  end

  context "when Gemfile dependencies have changed" do
    before do
      build_repo4 do
        build_gem "nokogiri", "1.16.4" do |s|
          s.platform = "arm64-darwin"
        end

        build_gem "nokogiri", "1.16.4" do |s|
          s.platform = "x86_64-linux"
        end

        build_gem "prism", "0.25.0"
      end

      gemfile <<~G
        source "https://gem.repo4"
        gem "nokogiri", ">=1.16.4"
        gem "prism", ">=0.25.0"
      G

      lockfile <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            nokogiri (1.16.4-arm64-darwin)
            nokogiri (1.16.4-x86_64-linux)

        PLATFORMS
          arm64-darwin
          x86_64-linux

        DEPENDENCIES
          nokogiri (>= 1.16.4)

        BUNDLED WITH
          #{Bundler::VERSION}
      L
    end

    it "still works" do
      simulate_platform "arm64-darwin-23" do
        bundle "update"
      end
    end
  end

  context "error handling" do
    before do
      gemfile "source 'https://gem.repo1'"
    end

    it "raises if too many flags are provided" do
      bundle "update --patch --minor", all: true, raise_on_error: false

      expect(err).to eq "Provide only one of the following options: minor, patch"
    end
  end
end
