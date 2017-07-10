# frozen_string_literal: true
require "spec_helper"

describe "bundle update" do
  before :each do
    build_repo2

    install_gemfile <<-G
      source "file://#{gem_repo2}"
      gem "activesupport"
      gem "rack-obama"
    G
  end

  describe "with no arguments" do
    it "updates the entire bundle" do
      update_repo2 do
        build_gem "activesupport", "3.0"
      end

      bundle "update"
      expect(out).to include("Bundle updated!")
      expect(the_bundle).to include_gems "rack 1.2", "rack-obama 1.0", "activesupport 3.0"
    end

    it "doesn't delete the Gemfile.lock file if something goes wrong" do
      gemfile <<-G
        source "file://#{gem_repo2}"
        gem "activesupport"
        gem "rack-obama"
        exit!
      G
      bundle "update"
      expect(bundled_app("Gemfile.lock")).to exist
    end
  end

  describe "--quiet argument" do
    it "hides UI messages" do
      bundle "update --quiet"
      expect(out).not_to include("Bundle updated!")
    end
  end

  describe "with a top level dependency" do
    it "unlocks all child dependencies that are unrelated to other locked dependencies" do
      update_repo2 do
        build_gem "activesupport", "3.0"
      end

      bundle "update rack-obama"
      expect(the_bundle).to include_gems "rack 1.2", "rack-obama 1.0", "activesupport 2.3.5"
    end
  end

  describe "with an unknown dependency" do
    it "should inform the user" do
      bundle "update halting-problem-solver"
      expect(out).to include "Could not find gem 'halting-problem-solver'"
    end
    it "should suggest alternatives" do
      bundle "update active-support"
      expect(out).to include "Did you mean activesupport?"
    end
  end

  describe "with a child dependency" do
    it "should update the child dependency" do
      update_repo2
      bundle "update rack"
      expect(the_bundle).to include_gems "rack 1.2"
    end
  end

  describe "when a possible resolve requires an older version of a locked gem" do
    context "and only_update_to_newer_versions is set" do
      before do
        bundle! "config only_update_to_newer_versions true"
      end
      it "does not go to an older version" do
        build_repo4 do
          build_gem "a" do |s|
            s.add_dependency "b"
            s.add_dependency "c"
          end
          build_gem "b"
          build_gem "c"
          build_gem "c", "2.0"
        end

        install_gemfile! <<-G
          source "file:#{gem_repo4}"
          gem "a"
        G

        expect(the_bundle).to include_gems("a 1.0", "b 1.0", "c 2.0")

        update_repo4 do
          build_gem "b", "2.0" do |s|
            s.add_dependency "c", "< 2"
          end
        end

        bundle! "update"

        expect(the_bundle).to include_gems("a 1.0", "b 1.0", "c 2.0")
      end
    end
  end

  describe "with --local option" do
    it "doesn't hit repo2" do
      FileUtils.rm_rf(gem_repo2)

      bundle "update --local"
      expect(out).not_to match(/Fetching source index/)
    end
  end

  describe "with --group option" do
    it "should update only specifed group gems" do
      install_gemfile <<-G
        source "file://#{gem_repo2}"
        gem "activesupport", :group => :development
        gem "rack"
      G
      update_repo2 do
        build_gem "activesupport", "3.0"
      end
      bundle "update --group development"
      expect(the_bundle).to include_gems "activesupport 3.0"
      expect(the_bundle).not_to include_gems "rack 1.2"
    end

    context "when there is a source with the same name as a gem in a group" do
      before :each do
        build_git "foo", :path => lib_path("activesupport")
        install_gemfile <<-G
          source "file://#{gem_repo2}"
          gem "activesupport", :group => :development
          gem "foo", :git => "#{lib_path("activesupport")}"
        G
      end

      it "should not update the gems from that source" do
        update_repo2 { build_gem "activesupport", "3.0" }
        update_git "foo", "2.0", :path => lib_path("activesupport")

        bundle "update --group development"
        expect(the_bundle).to include_gems "activesupport 3.0"
        expect(the_bundle).not_to include_gems "foo 2.0"
      end
    end
  end

  describe "in a frozen bundle" do
    it "should fail loudly" do
      bundle "install --deployment"
      bundle "update"

      expect(out).to match(/You are trying to install in deployment mode after changing.your Gemfile/m)
      expect(exitstatus).not_to eq(0) if exitstatus
    end
  end

  describe "with --source option" do
    it "should not update gems not included in the source that happen to have the same name" do
      pending("Allowed to fail to preserve backwards-compatibility")

      install_gemfile <<-G
        source "file://#{gem_repo2}"
        gem "activesupport"
      G
      update_repo2 { build_gem "activesupport", "3.0" }

      bundle "update --source activesupport"
      expect(the_bundle).not_to include_gems "activesupport 3.0"
    end

    it "should update gems not included in the source that happen to have the same name" do
      install_gemfile <<-G
        source "file://#{gem_repo2}"
        gem "activesupport"
      G
      update_repo2 { build_gem "activesupport", "3.0" }

      bundle "update --source activesupport"
      expect(the_bundle).to include_gems "activesupport 3.0"
    end
  end

  context "when there is a child dependency that is also in the gemfile" do
    before do
      build_repo2 do
        build_gem "fred", "1.0"
        build_gem "harry", "1.0" do |s|
          s.add_dependency "fred"
        end
      end

      install_gemfile <<-G
        source "file://#{gem_repo2}"
        gem "harry"
        gem "fred"
      G
    end

    it "should not update the child dependencies of a gem that has the same name as the source" do
      update_repo2 do
        build_gem "fred", "2.0"
        build_gem "harry", "2.0" do |s|
          s.add_dependency "fred"
        end
      end

      bundle "update --source harry"
      expect(the_bundle).to include_gems "harry 2.0"
      expect(the_bundle).to include_gems "fred 1.0"
    end
  end

  context "when there is a child dependency that appears elsewhere in the dependency graph" do
    before do
      build_repo2 do
        build_gem "fred", "1.0" do |s|
          s.add_dependency "george"
        end
        build_gem "george", "1.0"
        build_gem "harry", "1.0" do |s|
          s.add_dependency "george"
        end
      end

      install_gemfile <<-G
        source "file://#{gem_repo2}"
        gem "harry"
        gem "fred"
      G
    end

    it "should not update the child dependencies of a gem that has the same name as the source" do
      update_repo2 do
        build_gem "george", "2.0"
        build_gem "harry", "2.0" do |s|
          s.add_dependency "george"
        end
      end

      bundle "update --source harry"
      expect(the_bundle).to include_gems "harry 2.0"
      expect(the_bundle).to include_gems "fred 1.0"
      expect(the_bundle).to include_gems "george 1.0"
    end
  end
end

describe "bundle update in more complicated situations" do
  before :each do
    build_repo2
  end

  it "will eagerly unlock dependencies of a specified gem" do
    install_gemfile <<-G
      source "file://#{gem_repo2}"

      gem "thin"
      gem "rack-obama"
    G

    update_repo2 do
      build_gem "thin", "2.0" do |s|
        s.add_dependency "rack"
      end
    end

    bundle "update thin"
    expect(the_bundle).to include_gems "thin 2.0", "rack 1.2", "rack-obama 1.0"
  end

  it "will update only from pinned source" do
    install_gemfile <<-G
      source "file://#{gem_repo2}"

      source "file://#{gem_repo1}" do
        gem "thin"
      end
    G

    update_repo2 do
      build_gem "thin", "2.0"
    end

    bundle "update"
    expect(the_bundle).to include_gems "thin 1.0"
  end
end

describe "bundle update without a Gemfile.lock" do
  it "should not explode" do
    build_repo2

    gemfile <<-G
      source "file://#{gem_repo2}"

      gem "rack", "1.0"
    G

    bundle "update"

    expect(the_bundle).to include_gems "rack 1.0.0"
  end
end

describe "bundle update when a gem depends on a newer version of bundler" do
  before(:each) do
    build_repo2 do
      build_gem "rails", "3.0.1" do |s|
        s.add_dependency "bundler", Bundler::VERSION.succ
      end
    end

    gemfile <<-G
      source "file://#{gem_repo2}"
      gem "rails", "3.0.1"
    G
  end

  it "should not explode" do
    bundle "update"
    expect(err).to lack_errors
  end

  it "should explain that bundler conflicted" do
    bundle "update"
    expect(out).not_to match(/in snapshot/i)
    expect(out).to match(/current Bundler version/i)
    expect(out).to match(/perhaps you need to update bundler/i)
  end
end

describe "bundle update" do
  it "shows the previous version of the gem when updated from rubygems source" do
    build_repo2

    install_gemfile <<-G
      source "file://#{gem_repo2}"
      gem "activesupport"
    G

    bundle "update"
    expect(out).to include("Using activesupport 2.3.5")

    update_repo2 do
      build_gem "activesupport", "3.0"
    end

    bundle "update"
    expect(out).to include("Installing activesupport 3.0 (was 2.3.5)")
  end

  it "shows error message when Gemfile.lock is not preset and gem is specified" do
    install_gemfile <<-G
      source "file://#{gem_repo2}"
      gem "activesupport"
    G

    bundle "update nonexisting"
    expect(out).to include("This Bundle hasn't been installed yet. Run `bundle install` to update and install the bundled gems.")
    expect(exitstatus).to eq(22) if exitstatus
  end
end

describe "bundle update --ruby" do
  before do
    install_gemfile <<-G
        ::RUBY_VERSION = '2.1.3'
        ::RUBY_PATCHLEVEL = 100
        ruby '~> 2.1.0'
    G
    bundle "update --ruby"
  end

  context "when the Gemfile removes the ruby" do
    before do
      install_gemfile <<-G
          ::RUBY_VERSION = '2.1.4'
          ::RUBY_PATCHLEVEL = 222
      G
    end
    it "removes the Ruby from the Gemfile.lock" do
      bundle "update --ruby"

      lockfile_should_be <<-L
       GEM
         specs:

       PLATFORMS
         ruby

       DEPENDENCIES

       BUNDLED WITH
          #{Bundler::VERSION}
      L
    end
  end

  context "when the Gemfile specified an updated Ruby version" do
    before do
      install_gemfile <<-G
          ::RUBY_VERSION = '2.1.4'
          ::RUBY_PATCHLEVEL = 222
          ruby '~> 2.1.0'
      G
    end
    it "updates the Gemfile.lock with the latest version" do
      bundle "update --ruby"

      lockfile_should_be <<-L
       GEM
         specs:

       PLATFORMS
         ruby

       DEPENDENCIES

       RUBY VERSION
          ruby 2.1.4p222

       BUNDLED WITH
          #{Bundler::VERSION}
      L
    end
  end

  context "when a different Ruby is being used than has been versioned" do
    before do
      install_gemfile <<-G
          ::RUBY_VERSION = '2.2.2'
          ::RUBY_PATCHLEVEL = 505
          ruby '~> 2.1.0'
      G
    end
    it "shows a helpful error message" do
      bundle "update --ruby"

      expect(out).to include("Your Ruby version is 2.2.2, but your Gemfile specified ~> 2.1.0")
    end
  end

  context "when updating Ruby version and Gemfile `ruby`" do
    before do
      install_gemfile <<-G
          ::RUBY_VERSION = '1.8.3'
          ::RUBY_PATCHLEVEL = 55
          ruby '~> 1.8.0'
      G
    end
    it "updates the Gemfile.lock with the latest version" do
      bundle "update --ruby"

      lockfile_should_be <<-L
       GEM
         specs:

       PLATFORMS
         ruby

       DEPENDENCIES

       RUBY VERSION
          ruby 1.8.3p55

       BUNDLED WITH
          #{Bundler::VERSION}
      L
    end
  end
end

# these specs are slow and focus on integration and therefore are not exhaustive. unit specs elsewhere handle that.
describe "bundle update conservative" do
  context "patch and minor options" do
    before do
      build_repo4 do
        build_gem "foo", %w(1.4.3 1.4.4) do |s|
          s.add_dependency "bar", "~> 2.0"
        end
        build_gem "foo", %w(1.4.5 1.5.0) do |s|
          s.add_dependency "bar", "~> 2.1"
        end
        build_gem "foo", %w(1.5.1) do |s|
          s.add_dependency "bar", "~> 3.0"
        end
        build_gem "bar", %w(2.0.3 2.0.4 2.0.5 2.1.0 2.1.1 3.0.0)
        build_gem "qux", %w(1.0.0 1.0.1 1.1.0 2.0.0)
      end

      # establish a lockfile set to 1.4.3
      install_gemfile <<-G
        source "file://#{gem_repo4}"
        gem 'foo', '1.4.3'
        gem 'bar', '2.0.3'
        gem 'qux', '1.0.0'
      G

      # remove 1.4.3 requirement and bar altogether
      # to setup update specs below
      gemfile <<-G
        source "file://#{gem_repo4}"
        gem 'foo'
        gem 'qux'
      G
    end

    context "patch preferred" do
      it "single gem updates dependent gem to minor" do
        bundle "update --patch foo"

        expect(the_bundle).to include_gems "foo 1.4.5", "bar 2.1.1", "qux 1.0.0"
      end

      it "update all" do
        bundle "update --patch"

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
        bundle "update --minor --strict"

        expect(the_bundle).to include_gems "foo 1.5.0", "bar 2.1.1", "qux 1.1.0"
      end
    end
  end

  context "eager unlocking" do
    before do
      build_repo4 do
        build_gem "isolated_owner", %w(1.0.1 1.0.2) do |s|
          s.add_dependency "isolated_dep", "~> 2.0"
        end
        build_gem "isolated_dep", %w(2.0.1 2.0.2)

        build_gem "shared_owner_a", %w(3.0.1 3.0.2) do |s|
          s.add_dependency "shared_dep", "~> 5.0"
        end
        build_gem "shared_owner_b", %w(4.0.1 4.0.2) do |s|
          s.add_dependency "shared_dep", "~> 5.0"
        end
        build_gem "shared_dep", %w(5.0.1 5.0.2)
      end

      gemfile <<-G
        source "file://#{gem_repo4}"
        gem 'isolated_owner'

        gem 'shared_owner_a'
        gem 'shared_owner_b'
      G

      lockfile <<-L
        GEM
          remote: file://#{gem_repo4}
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
          ruby

        DEPENDENCIES
          shared_owner_a
          shared_owner_b
          isolated_owner

        BUNDLED WITH
           1.13.0
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

      expect(the_bundle).to include_gems "isolated_owner 1.0.2", "isolated_dep 2.0.2", "shared_dep 5.0.1", "shared_owner_a 3.0.2", "shared_owner_b 4.0.1"
    end

    it "should match bundle install conservative update behavior when not eagerly unlocking" do
      gemfile <<-G
        source "file://#{gem_repo4}"
        gem 'isolated_owner', '1.0.2'

        gem 'shared_owner_a', '3.0.2'
        gem 'shared_owner_b'
      G

      bundle "install"

      expect(the_bundle).to include_gems "isolated_owner 1.0.2", "isolated_dep 2.0.2", "shared_dep 5.0.1", "shared_owner_a 3.0.2", "shared_owner_b 4.0.1"
    end
  end

  context "error handling" do
    before do
      gemfile ""
    end

    it "raises if too many flags are provided" do
      bundle "update --patch --minor"

      expect(out).to eq "Provide only one of the following options: minor, patch"
    end
  end
end
