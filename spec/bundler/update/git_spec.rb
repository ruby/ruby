# frozen_string_literal: true

RSpec.describe "bundle update" do
  describe "git sources" do
    it "floats on a branch when :branch is used" do
      build_git "foo", "1.0"
      update_git "foo", :branch => "omg"

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        git "#{lib_path("foo-1.0")}", :branch => "omg" do
          gem 'foo'
        end
      G

      update_git "foo" do |s|
        s.write "lib/foo.rb", "FOO = '1.1'"
      end

      bundle "update", :all => true

      expect(the_bundle).to include_gems "foo 1.1"
    end

    it "updates correctly when you have like craziness" do
      build_lib "activesupport", "3.0", :path => lib_path("rails/activesupport")
      build_git "rails", "3.0", :path => lib_path("rails") do |s|
        s.add_dependency "activesupport", "= 3.0"
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rails", :git => "#{file_uri_for(lib_path("rails"))}"
      G

      bundle "update rails"
      expect(the_bundle).to include_gems "rails 3.0", "activesupport 3.0"
    end

    it "floats on a branch when :branch is used and the source is specified in the update" do
      build_git "foo", "1.0", :path => lib_path("foo")
      update_git "foo", :branch => "omg", :path => lib_path("foo")

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        git "#{lib_path("foo")}", :branch => "omg" do
          gem 'foo'
        end
      G

      update_git "foo", :path => lib_path("foo") do |s|
        s.write "lib/foo.rb", "FOO = '1.1'"
      end

      bundle "update --source foo"

      expect(the_bundle).to include_gems "foo 1.1"
    end

    it "floats on main when updating all gems that are pinned to the source even if you have child dependencies" do
      build_git "foo", :path => lib_path("foo")
      build_gem "bar", :to_bundle => true do |s|
        s.add_dependency "foo"
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "foo", :git => "#{file_uri_for(lib_path("foo"))}"
        gem "bar"
      G

      update_git "foo", :path => lib_path("foo") do |s|
        s.write "lib/foo.rb", "FOO = '1.1'"
      end

      bundle "update foo"

      expect(the_bundle).to include_gems "foo 1.1"
    end

    it "notices when you change the repo url in the Gemfile" do
      build_git "foo", :path => lib_path("foo_one")
      build_git "foo", :path => lib_path("foo_two")

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "foo", "1.0", :git => "#{file_uri_for(lib_path("foo_one"))}"
      G

      FileUtils.rm_rf lib_path("foo_one")

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "foo", "1.0", :git => "#{file_uri_for(lib_path("foo_two"))}"
      G

      expect(err).to be_empty
      expect(out).to include("Fetching #{file_uri_for(lib_path)}/foo_two")
      expect(out).to include("Bundle complete!")
    end

    it "fetches tags from the remote" do
      build_git "foo"
      @remote = build_git("bar", :bare => true)
      update_git "foo", :remote => file_uri_for(@remote.path)
      update_git "foo", :push => "main"

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'foo', :git => "#{@remote.path}"
      G

      # Create a new tag on the remote that needs fetching
      update_git "foo", :tag => "fubar"
      update_git "foo", :push => "fubar"

      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'foo', :git => "#{@remote.path}", :tag => "fubar"
      G

      bundle "update", :all => true
      expect(err).to be_empty
    end

    describe "with submodules" do
      before :each do
        # CVE-2022-39253: https://lore.kernel.org/lkml/xmqq4jw1uku5.fsf@gitster.g/
        system(*%W[git config --global protocol.file.allow always])

        build_repo4 do
          build_gem "submodule" do |s|
            s.write "lib/submodule.rb", "puts 'GEM'"
          end
        end

        build_git "submodule", "1.0" do |s|
          s.write "lib/submodule.rb", "puts 'GIT'"
        end

        build_git "has_submodule", "1.0" do |s|
          s.add_dependency "submodule"
        end

        sys_exec "git submodule add #{lib_path("submodule-1.0")} submodule-1.0", :dir => lib_path("has_submodule-1.0")
        sys_exec "git commit -m \"submodulator\"", :dir => lib_path("has_submodule-1.0")
      end

      it "it unlocks the source when submodules are added to a git source" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo4)}"
          git "#{lib_path("has_submodule-1.0")}" do
            gem "has_submodule"
          end
        G

        run "require 'submodule'"
        expect(out).to eq("GEM")

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo4)}"
          git "#{lib_path("has_submodule-1.0")}", :submodules => true do
            gem "has_submodule"
          end
        G

        run "require 'submodule'"
        expect(out).to eq("GIT")
      end

      it "unlocks the source when submodules are removed from git source", :git => ">= 2.9.0" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo4)}"
          git "#{lib_path("has_submodule-1.0")}", :submodules => true do
            gem "has_submodule"
          end
        G

        run "require 'submodule'"
        expect(out).to eq("GIT")

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo4)}"
          git "#{lib_path("has_submodule-1.0")}" do
            gem "has_submodule"
          end
        G

        run "require 'submodule'"
        expect(out).to eq("GEM")
      end
    end

    it "errors with a message when the .git repo is gone" do
      build_git "foo", "1.0"

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "foo", :git => "#{file_uri_for(lib_path("foo-1.0"))}"
      G

      lib_path("foo-1.0").join(".git").rmtree

      bundle :update, :all => true, :raise_on_error => false
      expect(err).to include(lib_path("foo-1.0").to_s).
        and match(/Git error: command `git fetch.+has failed/)
    end

    it "should not explode on invalid revision on update of gem by name" do
      build_git "rack", "0.8"

      build_git "rack", "0.8", :path => lib_path("local-rack") do |s|
        s.write "lib/rack.rb", "puts :LOCAL"
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack", :git => "#{file_uri_for(lib_path("rack-0.8"))}", :branch => "main"
      G

      bundle %(config set local.rack #{lib_path("local-rack")})
      bundle "update rack"
      expect(out).to include("Bundle updated!")
    end

    it "shows the previous version of the gem" do
      build_git "rails", "2.3.2", :path => lib_path("rails")

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rails", :git => "#{file_uri_for(lib_path("rails"))}"
      G

      update_git "rails", "3.0", :path => lib_path("rails"), :gemspec => true

      bundle "update", :all => true
      expect(out).to include("Using rails 3.0 (was 2.3.2) from #{file_uri_for(lib_path("rails"))} (at main@#{revision_for(lib_path("rails"))[0..6]})")
    end
  end

  describe "with --source flag" do
    before :each do
      build_repo2
      @git = build_git "foo", :path => lib_path("foo") do |s|
        s.executables = "foobar"
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        git "#{lib_path("foo")}" do
          gem 'foo'
        end
        gem 'rack'
      G
    end

    it "updates the source" do
      update_git "foo", :path => @git.path

      bundle "update --source foo"

      run <<-RUBY
        require 'foo'
        puts "WIN" if defined?(FOO_PREV_REF)
      RUBY

      expect(out).to eq("WIN")
    end

    it "unlocks gems that were originally pulled in by the source" do
      update_git "foo", "2.0", :path => @git.path

      bundle "update --source foo"
      expect(the_bundle).to include_gems "foo 2.0"
    end

    it "leaves all other gems frozen" do
      update_repo2
      update_git "foo", :path => @git.path

      bundle "update --source foo"
      expect(the_bundle).to include_gems "rack 1.0"
    end
  end

  context "when the gem and the repository have different names" do
    before :each do
      build_repo2
      @git = build_git "foo", :path => lib_path("bar")

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        git "#{lib_path("bar")}" do
          gem 'foo'
        end
        gem 'rack'
      G
    end

    it "the --source flag updates version of gems that were originally pulled in by the source" do
      spec_lines = lib_path("bar/foo.gemspec").read.split("\n")
      spec_lines[5] = "s.version = '2.0'"

      update_git "foo", "2.0", :path => @git.path do |s|
        s.write "foo.gemspec", spec_lines.join("\n")
      end

      ref = @git.ref_for "main"

      bundle "update --source bar"

      expect(lockfile).to eq <<~G
        GIT
          remote: #{@git.path}
          revision: #{ref}
          specs:
            foo (2.0)

        GEM
          remote: #{file_uri_for(gem_repo2)}/
          specs:
            rack (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          foo!
          rack

        CHECKSUMS
          foo (2.0)
          #{checksum_for_repo_gem gem_repo2, "rack", "1.0.0"}

        BUNDLED WITH
           #{Bundler::VERSION}
      G
    end
  end
end
