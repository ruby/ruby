# frozen_string_literal: true

RSpec.describe "bundle install with git sources" do
  describe "when floating on main" do
    let(:base_gemfile) do
      <<-G
        source "https://gem.repo1"
        git "#{lib_path("foo-1.0")}" do
          gem 'foo'
        end
      G
    end

    let(:install_base_gemfile) do
      build_git "foo" do |s|
        s.executables = "foobar"
      end

      install_gemfile base_gemfile
    end

    it "fetches gems" do
      install_base_gemfile
      expect(the_bundle).to include_gems("foo 1.0")

      run <<-RUBY
        require 'foo'
        puts "WIN" unless defined?(FOO_PREV_REF)
      RUBY

      expect(out).to eq("WIN")
    end

    it "points the installed copy's origin at the real remote, not the local cache" do
      install_base_gemfile

      installed = Pathname.glob(default_bundle_path("bundler/gems/foo-1.0-*")).first
      origin = git("config --get remote.origin.url", installed).strip
      expect(origin).to eq(lib_path("foo-1.0").to_s)
    end

    it "does not (yet?) enforce CHECKSUMS" do
      build_git "foo"
      revision = revision_for(lib_path("foo-1.0"))

      bundle_config "lockfile_checksums true"
      gemfile base_gemfile

      lockfile <<~L
        GIT
          remote: #{lib_path("foo-1.0")}
          revision: #{revision}
          specs:
            foo (1.0)

        GEM
          remote: https://gem.repo1/
          specs:

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          foo!

        CHECKSUMS
          foo (1.0)

        BUNDLED WITH
          #{Bundler::VERSION}
      L

      bundle_config "frozen true"

      bundle "install"
      expect(the_bundle).to include_gems("foo 1.0")
    end

    it "caches the git repo" do
      install_base_gemfile
      expect(Dir["#{default_cache_path}/git/foo-1.0-*"]).to have_attributes size: 1
    end

    it "does not write to cache on bundler/setup" do
      install_base_gemfile
      FileUtils.rm_r(default_cache_path)
      ruby "require 'bundler/setup'"
      expect(default_cache_path).not_to exist
    end

    it "caches the git repo globally and properly uses the cached repo on the next invocation" do
      install_base_gemfile
      pristine_system_gems
      bundle_config "global_gem_cache true"
      bundle :install
      expect(Dir["#{home}/.bundle/cache/git/foo-1.0-*"]).to have_attributes size: 1

      bundle "install --verbose"
      expect(err).to be_empty
      expect(out).to include("Using foo 1.0 from #{lib_path("foo")}")
    end

    it "caches the evaluated gemspec" do
      install_base_gemfile
      git = update_git "foo" do |s|
        s.executables = ["foobar"] # we added this the first time, so keep it now
        s.files = ["bin/foobar"] # updating git nukes the files list
        foospec = s.to_ruby.gsub(/s\.files.*/, 's.files = `git ls-files -z`.split("\x0")')
        s.write "foo.gemspec", foospec
      end

      bundle "update foo"

      sha = git.ref_for("main", 11)
      spec_file = default_bundle_path("bundler/gems/foo-1.0-#{sha}/foo.gemspec")
      expect(spec_file).to exist
      # Serialize with the RubyGems that wrote the file, since `#to_ruby`
      # output differs across RubyGems versions
      ruby "print Gem::Specification.load(#{spec_file.to_s.dump}).to_ruby"
      ruby_code = out
      file_code = File.read(spec_file)
      expect(file_code.strip).to eq(ruby_code)
    end

    it "does not update the git source implicitly" do
      install_base_gemfile
      update_git "foo"

      install_gemfile bundled_app2("Gemfile"), <<-G, dir: bundled_app2
        source "https://gem.repo1"
        git "#{lib_path("foo-1.0")}" do
          gem 'foo'
        end
      G

      run <<-RUBY
        require 'foo'
        puts "fail" if defined?(FOO_PREV_REF)
      RUBY

      expect(out).to be_empty
    end

    it "sets up git gem executables on the path" do
      install_base_gemfile
      bundle "exec foobar"
      expect(out).to eq("1.0")
    end

    it "complains if pinned specs don't exist in the git repo" do
      build_git "foo"

      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo1"
        gem "foo", "1.1", :git => "#{lib_path("foo-1.0")}"
      G

      expect(err).to include("The source contains the following gems matching 'foo':\n  * foo-1.0")
    end

    it "complains with version and platform if pinned specs don't exist in the git repo", :jruby_only do
      build_git "only_java" do |s|
        s.platform = "java"
      end

      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo1"
        platforms :jruby do
          gem "only_java", "1.2", :git => "#{lib_path("only_java-1.0-java")}"
        end
      G

      expect(err).to include("The source contains the following gems matching 'only_java':\n  * only_java-1.0-java")
    end

    it "complains with multiple versions and platforms if pinned specs don't exist in the git repo", :jruby_only do
      build_git "only_java", "1.0" do |s|
        s.platform = "java"
      end

      build_git "only_java", "1.1" do |s|
        s.platform = "java"
        s.write "only_java1-0.gemspec", File.read("#{lib_path("only_java-1.0-java")}/only_java.gemspec")
      end

      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo1"
        platforms :jruby do
          gem "only_java", "1.2", :git => "#{lib_path("only_java-1.1-java")}"
        end
      G

      expect(err).to include("The source contains the following gems matching 'only_java':\n  * only_java-1.0-java\n  * only_java-1.1-java")
    end

    it "still works after moving the application directory" do
      bundle_config "path vendor/bundle"
      install_base_gemfile

      FileUtils.mv bundled_app, tmp("bundled_app.bck")

      expect(the_bundle).to include_gems "foo 1.0", dir: tmp("bundled_app.bck")
    end

    it "can still install after moving the application directory" do
      bundle_config "path vendor/bundle"
      install_base_gemfile

      FileUtils.mv bundled_app, tmp("bundled_app.bck")

      update_git "foo", "1.1", path: lib_path("foo-1.0")

      gemfile tmp("bundled_app.bck/Gemfile"), <<-G
        source "https://gem.repo1"
        git "#{lib_path("foo-1.0")}" do
          gem 'foo'
        end

        gem "myrack", "1.0"
      G

      bundle "update foo", dir: tmp("bundled_app.bck")

      expect(the_bundle).to include_gems "foo 1.1", "myrack 1.0", dir: tmp("bundled_app.bck")
    end
  end

  describe "with an empty git block" do
    before do
      build_git "foo"
      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"

        git "#{lib_path("foo-1.0")}" do
          # this page left intentionally blank
        end
      G
    end

    it "does not explode" do
      bundle "install"
      expect(the_bundle).to include_gems "myrack 1.0"
    end
  end

  describe "when specifying a revision" do
    before(:each) do
      build_git "foo"
      @revision = revision_for(lib_path("foo-1.0"))
      update_git "foo"
    end

    it "works" do
      install_gemfile <<-G
        source "https://gem.repo1"
        git "#{lib_path("foo-1.0")}", :ref => "#{@revision}" do
          gem "foo"
        end
      G
      expect(err).to be_empty

      run <<-RUBY
        require 'foo'
        puts "WIN" unless defined?(FOO_PREV_REF)
      RUBY

      expect(out).to eq("WIN")
    end

    it "works when the revision is a symbol" do
      install_gemfile <<-G
        source "https://gem.repo1"
        git "#{lib_path("foo-1.0")}", :ref => #{@revision.to_sym.inspect} do
          gem "foo"
        end
      G
      expect(err).to be_empty

      run <<-RUBY
        require 'foo'
        puts "WIN" unless defined?(FOO_PREV_REF)
      RUBY

      expect(out).to eq("WIN")
    end

    it "works when an abbreviated revision is added after an initial, potentially shallow clone" do
      install_gemfile <<-G
        source "https://gem.repo1"
        git "#{lib_path("foo-1.0")}" do
          gem "foo"
        end
      G

      install_gemfile <<-G
        source "https://gem.repo1"
        git "#{lib_path("foo-1.0")}", :ref => #{@revision[0..7].inspect} do
          gem "foo"
        end
      G
    end

    it "works when a tag that does not look like a commit hash is used as the value of :ref" do
      build_git "foo"
      @remote = build_git("bar", bare: true)
      update_git "foo", remote: @remote.path
      update_git "foo", push: "main"

      install_gemfile <<-G
        source "https://gem.repo1"
        gem 'foo', :git => "#{@remote.path}"
      G

      # Create a new tag on the remote that needs fetching
      update_git "foo", tag: "v1.0.0"
      update_git "foo", push: "v1.0.0"

      install_gemfile <<-G
        source "https://gem.repo1"
        gem 'foo', :git => "#{@remote.path}", :ref => "v1.0.0"
      G

      expect(err).to be_empty
    end

    it "works when the revision is a non-head ref" do
      # want to ensure we don't fallback to main
      update_git "foo", path: lib_path("foo-1.0") do |s|
        s.write("lib/foo.rb", "raise 'FAIL'")
      end

      git("update-ref -m \"Bundler Spec!\" refs/bundler/1 main~1", lib_path("foo-1.0"))

      # want to ensure we don't fallback to HEAD
      update_git "foo", path: lib_path("foo-1.0"), branch: "rando" do |s|
        s.write("lib/foo.rb", "raise 'FAIL_FROM_RANDO'")
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        git "#{lib_path("foo-1.0")}", :ref => "refs/bundler/1" do
          gem "foo"
        end
      G
      expect(err).to be_empty

      run <<-RUBY
        require 'foo'
        puts "WIN" if defined?(FOO)
      RUBY

      expect(out).to eq("WIN")
    end

    it "works when the revision is a non-head ref and it was previously downloaded" do
      install_gemfile <<-G
        source "https://gem.repo1"
        git "#{lib_path("foo-1.0")}" do
          gem "foo"
        end
      G

      # want to ensure we don't fallback to main
      update_git "foo", path: lib_path("foo-1.0") do |s|
        s.write("lib/foo.rb", "raise 'FAIL'")
      end

      git("update-ref -m \"Bundler Spec!\" refs/bundler/1 main~1", lib_path("foo-1.0"))

      # want to ensure we don't fallback to HEAD
      update_git "foo", path: lib_path("foo-1.0"), branch: "rando" do |s|
        s.write("lib/foo.rb", "raise 'FAIL_FROM_RANDO'")
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        git "#{lib_path("foo-1.0")}", :ref => "refs/bundler/1" do
          gem "foo"
        end
      G
      expect(err).to be_empty

      run <<-RUBY
        require 'foo'
        puts "WIN" if defined?(FOO)
      RUBY

      expect(out).to eq("WIN")
    end

    it "does not download random non-head refs" do
      git("update-ref -m \"Bundler Spec!\" refs/bundler/1 main~1", lib_path("foo-1.0"))

      bundle_config "global_gem_cache true"

      install_gemfile <<-G
        source "https://gem.repo1"
        git "#{lib_path("foo-1.0")}" do
          gem "foo"
        end
      G

      # ensure we also git fetch after cloning
      bundle :update, all: true

      git("ls-remote .", Dir[home(".bundle/cache/git/foo-*")].first)

      expect(out).not_to include("refs/bundler/1")
    end
  end

  describe "when specifying a branch" do
    let(:branch) { "branch" }
    let(:repo) { build_git("foo").path }

    it "works" do
      update_git("foo", path: repo, branch: branch)

      install_gemfile <<-G
        source "https://gem.repo1"
        git "#{repo}", :branch => #{branch.dump} do
          gem "foo"
        end
      G

      expect(the_bundle).to include_gems("foo 1.0")
    end

    context "when the branch starts with a `#`" do
      let(:branch) { "#149/redirect-url-fragment" }
      it "works" do
        update_git("foo", path: repo, branch: branch)

        install_gemfile <<-G
          source "https://gem.repo1"
          git "#{repo}", :branch => #{branch.dump} do
            gem "foo"
          end
        G

        expect(the_bundle).to include_gems("foo 1.0")
      end
    end

    context "when the branch includes quotes" do
      let(:branch) { %('") }
      it "works" do
        skip "git does not accept this" if Gem.win_platform?

        update_git("foo", path: repo, branch: branch)

        install_gemfile <<-G
          source "https://gem.repo1"
          git "#{repo}", :branch => #{branch.dump} do
            gem "foo"
          end
        G

        expect(the_bundle).to include_gems("foo 1.0")
      end
    end
  end

  describe "when specifying a tag" do
    let(:tag) { "tag" }
    let(:repo) { build_git("foo").path }

    it "works" do
      update_git("foo", path: repo, tag: tag)

      install_gemfile <<-G
        source "https://gem.repo1"
        git "#{repo}", :tag => #{tag.dump} do
          gem "foo"
        end
      G

      expect(the_bundle).to include_gems("foo 1.0")
    end

    context "when the tag starts with a `#`" do
      let(:tag) { "#149/redirect-url-fragment" }
      it "works" do
        update_git("foo", path: repo, tag: tag)

        install_gemfile <<-G
          source "https://gem.repo1"
          git "#{repo}", :tag => #{tag.dump} do
            gem "foo"
          end
        G

        expect(the_bundle).to include_gems("foo 1.0")
      end
    end

    context "when the tag includes quotes" do
      let(:tag) { %('") }
      it "works" do
        skip "git does not accept this" if Gem.win_platform?

        update_git("foo", path: repo, tag: tag)

        install_gemfile <<-G
          source "https://gem.repo1"
          git "#{repo}", :tag => #{tag.dump} do
            gem "foo"
          end
        G

        expect(the_bundle).to include_gems("foo 1.0")
      end
    end
  end
end
