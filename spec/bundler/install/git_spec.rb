# frozen_string_literal: true

RSpec.describe "bundle install" do
  context "git sources" do
    it "displays the revision hash of the gem repository" do
      build_git "foo", "1.0", path: lib_path("foo")

      install_gemfile <<-G, verbose: true
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo")}"
      G

      expect(out).to include("Using foo 1.0 from #{lib_path("foo")} (at main@#{revision_for(lib_path("foo"))[0..6]})")
      expect(the_bundle).to include_gems "foo 1.0", source: "git@#{lib_path("foo")}"
    end

    it "displays the revision hash of the gem repository when passed a relative local path" do
      build_git "foo", "1.0", path: lib_path("foo")

      relative_path = lib_path("foo").relative_path_from(bundled_app)
      install_gemfile <<-G, verbose: true
        source "https://gem.repo1"
        gem "foo", :git => "#{relative_path}"
      G

      expect(out).to include("Using foo 1.0 from #{relative_path} (at main@#{revision_for(lib_path("foo"))[0..6]})")
      expect(the_bundle).to include_gems "foo 1.0", source: "git@#{lib_path("foo")}"
    end

    it "displays the correct default branch", git: ">= 2.28.0" do
      build_git "foo", "1.0", path: lib_path("foo"), default_branch: "main"

      install_gemfile <<-G, verbose: true
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo")}"
      G

      expect(out).to include("Using foo 1.0 from #{lib_path("foo")} (at main@#{revision_for(lib_path("foo"))[0..6]})")
      expect(the_bundle).to include_gems "foo 1.0", source: "git@#{lib_path("foo")}"
    end

    it "displays the ref of the gem repository when using branch~num as a ref" do
      skip "maybe branch~num notation doesn't work on Windows' git" if Gem.win_platform?

      build_git "foo", "1.0", path: lib_path("foo")
      rev = revision_for(lib_path("foo"))[0..6]
      update_git "foo", "2.0", path: lib_path("foo"), gemspec: true
      rev2 = revision_for(lib_path("foo"))[0..6]
      update_git "foo", "3.0", path: lib_path("foo"), gemspec: true

      install_gemfile <<-G, verbose: true
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo")}", :ref => "main~2"
      G

      expect(out).to include("Using foo 1.0 from #{lib_path("foo")} (at main~2@#{rev})")
      expect(the_bundle).to include_gems "foo 1.0", source: "git@#{lib_path("foo")}"

      update_git "foo", "4.0", path: lib_path("foo"), gemspec: true

      bundle :update, all: true, verbose: true
      expect(out).to include("Using foo 2.0 (was 1.0) from #{lib_path("foo")} (at main~2@#{rev2})")
      expect(the_bundle).to include_gems "foo 2.0", source: "git@#{lib_path("foo")}"
    end

    it "allows git repos that are missing but not being installed" do
      revision = build_git("foo").ref_for("HEAD")

      gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}", :group => :development
      G

      lockfile <<-L
        GIT
          remote: #{lib_path("foo-1.0")}
          revision: #{revision}
          specs:
            foo (1.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          foo!
      L

      bundle "config set --local path vendor/bundle"
      bundle "config set --local without development"
      bundle :install

      expect(out).to include("Bundle complete!")
    end

    it "allows multiple gems from the same git source" do
      build_repo2 do
        build_lib "foo", "1.0", path: lib_path("gems/foo")
        build_lib "zebra", "2.0", path: lib_path("gems/zebra")
        build_git "gems", path: lib_path("gems"), gemspec: false
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "foo", :git => "#{lib_path("gems")}", :glob => "foo/*.gemspec"
        gem "zebra", :git => "#{lib_path("gems")}", :glob => "zebra/*.gemspec"
      G

      bundle "info foo"
      expect(out).to include("* foo (1.0 #{revision_for(lib_path("gems"))[0..6]})")

      bundle "info zebra"
      expect(out).to include("* zebra (2.0 #{revision_for(lib_path("gems"))[0..6]})")
    end

    it "should always sort dependencies in the same order" do
      # This Gemfile + lockfile had a problem where the first
      # `bundle install` would change the order, but the second would
      # change it back.

      # NOTE: both gems MUST have the same path! It has to be two gems in one repo.

      test = build_git "test", "1.0.0", path: lib_path("test-and-other")
      other = build_git "other", "1.0.0", path: lib_path("test-and-other")
      test_ref = test.ref_for("HEAD")
      other_ref = other.ref_for("HEAD")

      gemfile <<-G
        source "https://gem.repo1"

        gem "test", git: #{test.path.to_s.inspect}
        gem "other", ref: #{other_ref.inspect}, git: #{other.path.to_s.inspect}
      G

      lockfile <<-L
        GIT
          remote: #{test.path}
          revision: #{test_ref}
          specs:
            test (1.0.0)

        GIT
          remote: #{other.path}
          revision: #{other_ref}
          ref: #{other_ref}
          specs:
            other (1.0.0)

        GEM
          remote: https://gem.repo1/
          specs:

        PLATFORMS
          ruby

        DEPENDENCIES
          other!
          test!

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      # If GH#6743 is present, the first `bundle install` will change the
      # lockfile, by flipping the order (`other` would be moved to the top).
      #
      # The second `bundle install` would then change the lockfile back
      # to the original.
      #
      # The fix makes it so it may change it once, but it will not change
      # it a second time.
      #
      # So, we run `bundle install` once, and store the value of the
      # modified lockfile.
      bundle :install
      modified_lockfile = lockfile

      # If GH#6743 is present, the second `bundle install` would change the
      # lockfile back to what it was originally.
      #
      # This `expect` makes sure it doesn't change a second time.
      bundle :install
      expect(lockfile).to eq(modified_lockfile)

      expect(out).to include("Bundle complete!")
    end

    it "allows older revisions of git source when clean true" do
      build_git "foo", "1.0", path: lib_path("foo")
      rev = revision_for(lib_path("foo"))

      bundle "config set path vendor/bundle"
      bundle "config set clean true"
      install_gemfile <<-G, verbose: true
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo")}"
      G

      expect(out).to include("Using foo 1.0 from #{lib_path("foo")} (at main@#{rev[0..6]})")
      expect(the_bundle).to include_gems "foo 1.0", source: "git@#{lib_path("foo")}"

      old_lockfile = lockfile

      update_git "foo", "2.0", path: lib_path("foo"), gemspec: true
      rev2 = revision_for(lib_path("foo"))

      bundle :update, all: true, verbose: true
      expect(out).to include("Using foo 2.0 (was 1.0) from #{lib_path("foo")} (at main@#{rev2[0..6]})")
      expect(out).to include("Removing foo (#{rev[0..11]})")
      expect(the_bundle).to include_gems "foo 2.0", source: "git@#{lib_path("foo")}"

      lockfile(old_lockfile)

      bundle :install, verbose: true
      expect(out).to include("Using foo 1.0 from #{lib_path("foo")} (at main@#{rev[0..6]})")
      expect(the_bundle).to include_gems "foo 1.0", source: "git@#{lib_path("foo")}"
    end

    context "when install directory exists" do
      let(:checkout_confirmation_log_message) { "Checking out revision" }
      let(:using_foo_confirmation_log_message) { "Using foo 1.0 from #{lib_path("foo")} (at main@#{revision_for(lib_path("foo"))[0..6]})" }

      context "and no contents besides .git directory are present" do
        it "reinstalls gem" do
          build_git "foo", "1.0", path: lib_path("foo")

          gemfile = <<-G
            source "https://gem.repo1"
            gem "foo", :git => "#{lib_path("foo")}"
          G

          install_gemfile gemfile, verbose: true

          expect(out).to include(checkout_confirmation_log_message)
          expect(out).to include(using_foo_confirmation_log_message)
          expect(the_bundle).to include_gems "foo 1.0", source: "git@#{lib_path("foo")}"

          # validate that the installed directory exists and has some expected contents
          install_directory = default_bundle_path("bundler/gems/foo-#{revision_for(lib_path("foo"))[0..11]}")
          dot_git_directory = install_directory.join(".git")
          lib_directory = install_directory.join("lib")
          gemspec = install_directory.join("foo.gemspec")
          expect([install_directory, dot_git_directory, lib_directory, gemspec]).to all exist

          # remove all elements in the install directory except .git directory
          FileUtils.rm_r(lib_directory)
          gemspec.delete

          expect(dot_git_directory).to exist
          expect(lib_directory).not_to exist
          expect(gemspec).not_to exist

          # rerun bundle install
          install_gemfile gemfile, verbose: true

          expect(out).to include(checkout_confirmation_log_message)
          expect(out).to include(using_foo_confirmation_log_message)
          expect(the_bundle).to include_gems "foo 1.0", source: "git@#{lib_path("foo")}"

          # validate that it reinstalls all components
          expect([install_directory, dot_git_directory, lib_directory, gemspec]).to all exist
        end
      end

      context "and contents besides .git directory are present" do
        # we want to confirm that the change to try to detect partial installs and reinstall does not
        # result in repeatedly reinstalling the gem when it is fully installed
        it "does not reinstall gem" do
          build_git "foo", "1.0", path: lib_path("foo")

          gemfile = <<-G
            source "https://gem.repo1"
            gem "foo", :git => "#{lib_path("foo")}"
          G

          install_gemfile gemfile, verbose: true

          expect(out).to include(checkout_confirmation_log_message)
          expect(out).to include(using_foo_confirmation_log_message)
          expect(the_bundle).to include_gems "foo 1.0", source: "git@#{lib_path("foo")}"

          # rerun bundle install
          install_gemfile gemfile, verbose: true

          # it isn't altogether straight-forward to validate that bundle didn't do soething on the second run, however,
          # the presence of the 2nd log message confirms install got past the point that it would have logged the above if
          # it was going to
          expect(out).not_to include(checkout_confirmation_log_message)
          expect(out).to include(using_foo_confirmation_log_message)
        end
      end
    end
  end
end
