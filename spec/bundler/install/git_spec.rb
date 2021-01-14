# frozen_string_literal: true

RSpec.describe "bundle install" do
  context "git sources" do
    it "displays the revision hash of the gem repository" do
      build_git "foo", "1.0", :path => lib_path("foo")

      install_gemfile <<-G, :verbose => true
        gem "foo", :git => "#{file_uri_for(lib_path("foo"))}"
      G

      expect(out).to include("Using foo 1.0 from #{file_uri_for(lib_path("foo"))} (at master@#{revision_for(lib_path("foo"))[0..6]})")
      expect(the_bundle).to include_gems "foo 1.0", :source => "git@#{lib_path("foo")}"
    end

    it "displays the correct default branch" do
      build_git "foo", "1.0", :path => lib_path("foo"), :default_branch => "main"

      install_gemfile <<-G, :verbose => true
        gem "foo", :git => "#{file_uri_for(lib_path("foo"))}"
      G

      expect(out).to include("Using foo 1.0 from #{file_uri_for(lib_path("foo"))} (at main@#{revision_for(lib_path("foo"))[0..6]})")
      expect(the_bundle).to include_gems "foo 1.0", :source => "git@#{lib_path("foo")}"
    end

    it "displays the ref of the gem repository when using branch~num as a ref" do
      skip "maybe branch~num notation doesn't work on Windows' git" if Gem.win_platform?

      build_git "foo", "1.0", :path => lib_path("foo")
      rev = revision_for(lib_path("foo"))[0..6]
      update_git "foo", "2.0", :path => lib_path("foo"), :gemspec => true
      rev2 = revision_for(lib_path("foo"))[0..6]
      update_git "foo", "3.0", :path => lib_path("foo"), :gemspec => true

      install_gemfile <<-G, :verbose => true
        gem "foo", :git => "#{file_uri_for(lib_path("foo"))}", :ref => "master~2"
      G

      expect(out).to include("Using foo 1.0 from #{file_uri_for(lib_path("foo"))} (at master~2@#{rev})")
      expect(the_bundle).to include_gems "foo 1.0", :source => "git@#{lib_path("foo")}"

      update_git "foo", "4.0", :path => lib_path("foo"), :gemspec => true

      bundle :update, :all => true, :verbose => true
      expect(out).to include("Using foo 2.0 (was 1.0) from #{file_uri_for(lib_path("foo"))} (at master~2@#{rev2})")
      expect(the_bundle).to include_gems "foo 2.0", :source => "git@#{lib_path("foo")}"
    end

    it "should allows git repos that are missing but not being installed" do
      revision = build_git("foo").ref_for("HEAD")

      gemfile <<-G
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

      bundle "config --local path vendor/bundle"
      bundle "config --local without development"
      bundle :install

      expect(out).to include("Bundle complete!")
    end

    it "allows multiple gems from the same git source" do
      build_repo2 do
        build_lib "foo", "1.0", :path => lib_path("gems/foo")
        build_lib "zebra", "2.0", :path => lib_path("gems/zebra")
        build_git "gems", :path => lib_path("gems"), :gemspec => false
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
  end
end
