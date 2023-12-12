# frozen_string_literal: true

RSpec.describe "bundle install" do
  context "git sources" do
    it "displays the revision hash of the gem repository" do
      build_git "foo", "1.0", path: lib_path("foo")

      install_gemfile <<-G, verbose: true
        source "#{file_uri_for(gem_repo1)}"
        gem "foo", :git => "#{file_uri_for(lib_path("foo"))}"
      G

      expect(out).to include("Using foo 1.0 from #{file_uri_for(lib_path("foo"))} (at main@#{revision_for(lib_path("foo"))[0..6]})")
      expect(the_bundle).to include_gems "foo 1.0", source: "git@#{lib_path("foo")}"
    end

    it "displays the correct default branch", git: ">= 2.28.0" do
      build_git "foo", "1.0", path: lib_path("foo"), default_branch: "main"

      install_gemfile <<-G, verbose: true
        source "#{file_uri_for(gem_repo1)}"
        gem "foo", :git => "#{file_uri_for(lib_path("foo"))}"
      G

      expect(out).to include("Using foo 1.0 from #{file_uri_for(lib_path("foo"))} (at main@#{revision_for(lib_path("foo"))[0..6]})")
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
        source "#{file_uri_for(gem_repo1)}"
        gem "foo", :git => "#{file_uri_for(lib_path("foo"))}", :ref => "main~2"
      G

      expect(out).to include("Using foo 1.0 from #{file_uri_for(lib_path("foo"))} (at main~2@#{rev})")
      expect(the_bundle).to include_gems "foo 1.0", source: "git@#{lib_path("foo")}"

      update_git "foo", "4.0", path: lib_path("foo"), gemspec: true

      bundle :update, all: true, verbose: true
      expect(out).to include("Using foo 2.0 (was 1.0) from #{file_uri_for(lib_path("foo"))} (at main~2@#{rev2})")
      expect(the_bundle).to include_gems "foo 2.0", source: "git@#{lib_path("foo")}"
    end

    it "should allows git repos that are missing but not being installed" do
      revision = build_git("foo").ref_for("HEAD")

      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "foo", :git => "#{file_uri_for(lib_path("foo-1.0"))}", :group => :development
      G

      lockfile <<-L
        GIT
          remote: #{file_uri_for(lib_path("foo-1.0"))}
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
        source "#{file_uri_for(gem_repo2)}"
        gem "foo", :git => "#{file_uri_for(lib_path("gems"))}", :glob => "foo/*.gemspec"
        gem "zebra", :git => "#{file_uri_for(lib_path("gems"))}", :glob => "zebra/*.gemspec"
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
        source "#{file_uri_for(gem_repo1)}"

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
          remote: #{file_uri_for(gem_repo1)}/
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
        source "#{file_uri_for(gem_repo1)}"
        gem "foo", :git => "#{file_uri_for(lib_path("foo"))}"
      G

      expect(out).to include("Using foo 1.0 from #{file_uri_for(lib_path("foo"))} (at main@#{rev[0..6]})")
      expect(the_bundle).to include_gems "foo 1.0", source: "git@#{lib_path("foo")}"

      old_lockfile = lockfile

      update_git "foo", "2.0", path: lib_path("foo"), gemspec: true
      rev2 = revision_for(lib_path("foo"))

      bundle :update, all: true, verbose: true
      expect(out).to include("Using foo 2.0 (was 1.0) from #{file_uri_for(lib_path("foo"))} (at main@#{rev2[0..6]})")
      expect(out).to include("Removing foo (#{rev[0..11]})")
      expect(the_bundle).to include_gems "foo 2.0", source: "git@#{lib_path("foo")}"

      lockfile(old_lockfile)

      bundle :install, verbose: true
      expect(out).to include("Using foo 1.0 from #{file_uri_for(lib_path("foo"))} (at main@#{rev[0..6]})")
      expect(the_bundle).to include_gems "foo 1.0", source: "git@#{lib_path("foo")}"
    end
  end
end
