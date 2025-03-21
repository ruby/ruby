# frozen_string_literal: true

RSpec.describe "bundle install with git sources" do
  describe "when floating on main" do
    before :each do
      build_git "foo" do |s|
        s.executables = "foobar"
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        git "#{lib_path("foo-1.0")}" do
          gem 'foo'
        end
      G
    end

    it "fetches gems" do
      expect(the_bundle).to include_gems("foo 1.0")

      run <<-RUBY
        require 'foo'
        puts "WIN" unless defined?(FOO_PREV_REF)
      RUBY

      expect(out).to eq("WIN")
    end

    it "caches the git repo", bundler: "< 3" do
      expect(Dir["#{default_bundle_path}/cache/bundler/git/foo-1.0-*"]).to have_attributes size: 1
    end

    it "does not write to cache on bundler/setup" do
      FileUtils.rm_r(default_cache_path)
      ruby "require 'bundler/setup'"
      expect(default_cache_path).not_to exist
    end

    it "caches the git repo globally and properly uses the cached repo on the next invocation" do
      pristine_system_gems :bundler
      bundle "config set global_gem_cache true"
      bundle :install
      expect(Dir["#{home}/.bundle/cache/git/foo-1.0-*"]).to have_attributes size: 1

      bundle "install --verbose"
      expect(err).to be_empty
      expect(out).to include("Using foo 1.0 from #{lib_path("foo")}")
    end

    it "caches the evaluated gemspec" do
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
      ruby_code = Gem::Specification.load(spec_file.to_s).to_ruby
      file_code = File.read(spec_file)
      expect(file_code).to eq(ruby_code)
    end

    it "does not update the git source implicitly" do
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
      bundle "config set --local path vendor/bundle"
      bundle "install"

      FileUtils.mv bundled_app, tmp("bundled_app.bck")

      expect(the_bundle).to include_gems "foo 1.0", dir: tmp("bundled_app.bck")
    end

    it "can still install after moving the application directory" do
      bundle "config set --local path vendor/bundle"
      bundle "install"

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

      bundle "config set global_gem_cache true"

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

  describe "when specifying local override" do
    it "uses the local repository instead of checking a new one out" do
      build_git "myrack", "0.8", path: lib_path("local-myrack") do |s|
        s.write "lib/myrack.rb", "puts :LOCAL"
      end

      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}", :branch => "main"
      G

      bundle %(config set local.myrack #{lib_path("local-myrack")})
      bundle :install

      run "require 'myrack'"
      expect(out).to eq("LOCAL")
    end

    it "chooses the local repository on runtime" do
      build_git "myrack", "0.8"

      FileUtils.cp_r("#{lib_path("myrack-0.8")}/.", lib_path("local-myrack"))

      update_git "myrack", "0.8", path: lib_path("local-myrack") do |s|
        s.write "lib/myrack.rb", "puts :LOCAL"
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}", :branch => "main"
      G

      bundle %(config set local.myrack #{lib_path("local-myrack")})
      run "require 'myrack'"
      expect(out).to eq("LOCAL")
    end

    it "unlocks the source when the dependencies have changed while switching to the local" do
      build_git "myrack", "0.8"

      FileUtils.cp_r("#{lib_path("myrack-0.8")}/.", lib_path("local-myrack"))

      update_git "myrack", "0.8", path: lib_path("local-myrack") do |s|
        s.write "myrack.gemspec", build_spec("myrack", "0.8") { runtime "rspec", "> 0" }.first.to_ruby
        s.write "lib/myrack.rb", "puts :LOCAL"
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}", :branch => "main"
      G

      bundle %(config set local.myrack #{lib_path("local-myrack")})
      bundle :install
      run "require 'myrack'"
      expect(out).to eq("LOCAL")
    end

    it "updates specs on runtime" do
      system_gems "nokogiri-1.4.2"

      build_git "myrack", "0.8"

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}", :branch => "main"
      G

      lockfile0 = File.read(bundled_app_lock)

      FileUtils.cp_r("#{lib_path("myrack-0.8")}/.", lib_path("local-myrack"))
      update_git "myrack", "0.8", path: lib_path("local-myrack") do |s|
        s.add_dependency "nokogiri", "1.4.2"
      end

      bundle %(config set local.myrack #{lib_path("local-myrack")})
      run "require 'myrack'"

      lockfile1 = File.read(bundled_app_lock)
      expect(lockfile1).not_to eq(lockfile0)
    end

    it "updates ref on install" do
      build_git "myrack", "0.8"

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}", :branch => "main"
      G

      lockfile0 = File.read(bundled_app_lock)

      FileUtils.cp_r("#{lib_path("myrack-0.8")}/.", lib_path("local-myrack"))
      update_git "myrack", "0.8", path: lib_path("local-myrack")

      bundle %(config set local.myrack #{lib_path("local-myrack")})
      bundle :install

      lockfile1 = File.read(bundled_app_lock)
      expect(lockfile1).not_to eq(lockfile0)
    end

    it "explodes and gives correct solution if given path does not exist on install" do
      build_git "myrack", "0.8"

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}", :branch => "main"
      G

      bundle %(config set local.myrack #{lib_path("local-myrack")})
      bundle :install, raise_on_error: false
      expect(err).to match(/Cannot use local override for myrack-0.8 because #{Regexp.escape(lib_path("local-myrack").to_s)} does not exist/)

      solution = "config unset local.myrack"
      expect(err).to match(/Run `bundle #{solution}` to remove the local override/)

      bundle solution
      bundle :install

      expect(err).to be_empty
    end

    it "explodes and gives correct solution if branch is not given on install" do
      build_git "myrack", "0.8"
      FileUtils.cp_r("#{lib_path("myrack-0.8")}/.", lib_path("local-myrack"))

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}"
      G

      bundle %(config set local.myrack #{lib_path("local-myrack")})
      bundle :install, raise_on_error: false
      expect(err).to match(/Cannot use local override for myrack-0.8 at #{Regexp.escape(lib_path("local-myrack").to_s)} because :branch is not specified in Gemfile/)

      solution = "config unset local.myrack"
      expect(err).to match(/Specify a branch or run `bundle #{solution}` to remove the local override/)

      bundle solution
      bundle :install

      expect(err).to be_empty
    end

    it "does not explode if disable_local_branch_check is given" do
      build_git "myrack", "0.8"
      FileUtils.cp_r("#{lib_path("myrack-0.8")}/.", lib_path("local-myrack"))

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}"
      G

      bundle %(config set local.myrack #{lib_path("local-myrack")})
      bundle %(config set disable_local_branch_check true)
      bundle :install
      expect(out).to match(/Bundle complete!/)
    end

    it "explodes on different branches on install" do
      build_git "myrack", "0.8"

      FileUtils.cp_r("#{lib_path("myrack-0.8")}/.", lib_path("local-myrack"))

      update_git "myrack", "0.8", path: lib_path("local-myrack"), branch: "another" do |s|
        s.write "lib/myrack.rb", "puts :LOCAL"
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}", :branch => "main"
      G

      bundle %(config set local.myrack #{lib_path("local-myrack")})
      bundle :install, raise_on_error: false
      expect(err).to match(/is using branch another but Gemfile specifies main/)
    end

    it "explodes on invalid revision on install" do
      build_git "myrack", "0.8"

      build_git "myrack", "0.8", path: lib_path("local-myrack") do |s|
        s.write "lib/myrack.rb", "puts :LOCAL"
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}", :branch => "main"
      G

      bundle %(config set local.myrack #{lib_path("local-myrack")})
      bundle :install, raise_on_error: false
      expect(err).to match(/The Gemfile lock is pointing to revision \w+/)
    end

    it "does not explode on invalid revision on install" do
      build_git "myrack", "0.8"

      build_git "myrack", "0.8", path: lib_path("local-myrack") do |s|
        s.write "lib/myrack.rb", "puts :LOCAL"
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}", :branch => "main"
      G

      bundle %(config set local.myrack #{lib_path("local-myrack")})
      bundle %(config set disable_local_revision_check true)
      bundle :install
      expect(out).to match(/Bundle complete!/)
    end
  end

  describe "specified inline" do
    # TODO: Figure out how to write this test so that it is not flaky depending
    #       on the current network situation.
    # it "supports private git URLs" do
    #   gemfile <<-G
    #     gem "thingy", :git => "git@notthere.fallingsnow.net:somebody/thingy.git"
    #   G
    #
    #   bundle :install
    #
    #   # p out
    #   # p err
    #   puts err unless err.empty? # This spec fails randomly every so often
    #   err.should include("notthere.fallingsnow.net")
    #   err.should include("ssh")
    # end

    it "installs from git even if a newer gem is available elsewhere" do
      build_git "myrack", "0.8"

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack-0.8")}"
      G

      expect(the_bundle).to include_gems "myrack 0.8"
    end

    it "installs dependencies from git even if a newer gem is available elsewhere" do
      system_gems "myrack-1.0.0"

      build_lib "myrack", "1.0", path: lib_path("nested/bar") do |s|
        s.write "lib/myrack.rb", "puts 'WIN OVERRIDE'"
      end

      build_git "foo", path: lib_path("nested") do |s|
        s.add_dependency "myrack", "= 1.0"
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("nested")}"
      G

      run "require 'myrack'"
      expect(out).to eq("WIN OVERRIDE")
    end

    it "correctly unlocks when changing to a git source" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", "0.9.1"
      G

      build_git "myrack", path: lib_path("myrack")

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", "1.0.0", :git => "#{lib_path("myrack")}"
      G

      expect(the_bundle).to include_gems "myrack 1.0.0"
    end

    it "correctly unlocks when changing to a git source without versions" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      build_git "myrack", "1.2", path: lib_path("myrack")

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", :git => "#{lib_path("myrack")}"
      G

      expect(the_bundle).to include_gems "myrack 1.2"
    end
  end

  describe "block syntax" do
    it "pulls all gems from a git block" do
      build_lib "omg", path: lib_path("hi2u/omg")
      build_lib "hi2u", path: lib_path("hi2u")

      install_gemfile <<-G
        source "https://gem.repo1"
        path "#{lib_path("hi2u")}" do
          gem "omg"
          gem "hi2u"
        end
      G

      expect(the_bundle).to include_gems "omg 1.0", "hi2u 1.0"
    end
  end

  it "uses a ref if specified" do
    build_git "foo"
    @revision = revision_for(lib_path("foo-1.0"))
    update_git "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => "#{lib_path("foo-1.0")}", :ref => "#{@revision}"
    G

    run <<-RUBY
      require 'foo'
      puts "WIN" unless defined?(FOO_PREV_REF)
    RUBY

    expect(out).to eq("WIN")
  end

  it "correctly handles cases with invalid gemspecs" do
    build_git "foo" do |s|
      s.summary = nil
    end

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => "#{lib_path("foo-1.0")}"
      gem "rails", "2.3.2"
    G

    expect(the_bundle).to include_gems "foo 1.0"
    expect(the_bundle).to include_gems "rails 2.3.2"
  end

  it "runs the gemspec in the context of its parent directory" do
    build_lib "bar", path: lib_path("foo/bar"), gemspec: false do |s|
      s.write lib_path("foo/bar/lib/version.rb"), %(BAR_VERSION = '1.0')
      s.write "bar.gemspec", <<-G
        $:.unshift Dir.pwd
        require 'lib/version'
        Gem::Specification.new do |s|
          s.name        = 'bar'
          s.author      = 'no one'
          s.version     = BAR_VERSION
          s.summary     = 'Bar'
          s.files       = Dir["lib/**/*.rb"]
        end
      G
    end

    build_git "foo", path: lib_path("foo") do |s|
      s.write "bin/foo", ""
    end

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "bar", :git => "#{lib_path("foo")}"
      gem "rails", "2.3.2"
    G

    expect(the_bundle).to include_gems "bar 1.0"
    expect(the_bundle).to include_gems "rails 2.3.2"
  end

  it "runs the gemspec in the context of its parent directory, when using local overrides" do
    build_git "foo", path: lib_path("foo"), gemspec: false do |s|
      s.write lib_path("foo/lib/foo/version.rb"), %(FOO_VERSION = '1.0')
      s.write "foo.gemspec", <<-G
        $:.unshift Dir.pwd
        require 'lib/foo/version'
        Gem::Specification.new do |s|
          s.name        = 'foo'
          s.author      = 'no one'
          s.version     = FOO_VERSION
          s.summary     = 'Foo'
          s.files       = Dir["lib/**/*.rb"]
        end
      G
    end

    gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => "https://github.com/gems/foo", branch: "main"
    G

    bundle %(config set local.foo #{lib_path("foo")})

    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "installs from git even if a rubygems gem is present" do
    build_gem "foo", "1.0", path: lib_path("fake_foo"), to_system: true do |s|
      s.write "lib/foo.rb", "raise 'FAIL'"
    end

    build_git "foo", "1.0"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", "1.0", :git => "#{lib_path("foo-1.0")}"
    G

    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "fakes the gem out if there is no gemspec" do
    build_git "foo", gemspec: false

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", "1.0", :git => "#{lib_path("foo-1.0")}"
      gem "rails", "2.3.2"
    G

    expect(the_bundle).to include_gems("foo 1.0")
    expect(the_bundle).to include_gems("rails 2.3.2")
  end

  it "catches git errors and spits out useful output" do
    gemfile <<-G
      source "https://gem.repo1"
      gem "foo", "1.0", :git => "omgomg"
    G

    bundle :install, raise_on_error: false

    expect(err).to include("Git error:")
    expect(err).to include("fatal")
    expect(err).to include("omgomg")
  end

  it "works when the gem path has spaces in it" do
    build_git "foo", path: lib_path("foo space-1.0")

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => "#{lib_path("foo space-1.0")}"
    G

    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "handles repos that have been force-pushed" do
    build_git "forced", "1.0"

    install_gemfile <<-G
      source "https://gem.repo1"
      git "#{lib_path("forced-1.0")}" do
        gem 'forced'
      end
    G
    expect(the_bundle).to include_gems "forced 1.0"

    update_git "forced" do |s|
      s.write "lib/forced.rb", "FORCED = '1.1'"
    end

    bundle "update", all: true
    expect(the_bundle).to include_gems "forced 1.1"

    git("reset --hard HEAD^", lib_path("forced-1.0"))

    bundle "update", all: true
    expect(the_bundle).to include_gems "forced 1.0"
  end

  it "ignores submodules if :submodule is not passed" do
    # CVE-2022-39253: https://lore.kernel.org/lkml/xmqq4jw1uku5.fsf@gitster.g/
    system(*%W[git config --global protocol.file.allow always])

    build_git "submodule", "1.0"
    build_git "has_submodule", "1.0" do |s|
      s.add_dependency "submodule"
    end
    git "submodule add #{lib_path("submodule-1.0")} submodule-1.0", lib_path("has_submodule-1.0")
    git "commit -m \"submodulator\"", lib_path("has_submodule-1.0")

    install_gemfile <<-G, raise_on_error: false
      source "https://gem.repo1"
      git "#{lib_path("has_submodule-1.0")}" do
        gem "has_submodule"
      end
    G
    expect(err).to match(%r{submodule >= 0 could not be found in rubygems repository https://gem.repo1/ or installed locally})

    expect(the_bundle).not_to include_gems "has_submodule 1.0"
  end

  it "handles repos with submodules" do
    # CVE-2022-39253: https://lore.kernel.org/lkml/xmqq4jw1uku5.fsf@gitster.g/
    system(*%W[git config --global protocol.file.allow always])

    build_git "submodule", "1.0"
    build_git "has_submodule", "1.0" do |s|
      s.add_dependency "submodule"
    end
    git "submodule add #{lib_path("submodule-1.0")} submodule-1.0", lib_path("has_submodule-1.0")
    git "commit -m \"submodulator\"", lib_path("has_submodule-1.0")

    install_gemfile <<-G
      source "https://gem.repo1"
      git "#{lib_path("has_submodule-1.0")}", :submodules => true do
        gem "has_submodule"
      end
    G

    expect(the_bundle).to include_gems "has_submodule 1.0"
  end

  it "does not warn when deiniting submodules" do
    # CVE-2022-39253: https://lore.kernel.org/lkml/xmqq4jw1uku5.fsf@gitster.g/
    system(*%W[git config --global protocol.file.allow always])

    build_git "submodule", "1.0"
    build_git "has_submodule", "1.0"

    git "submodule add #{lib_path("submodule-1.0")} submodule-1.0", lib_path("has_submodule-1.0")
    git "commit -m \"submodulator\"", lib_path("has_submodule-1.0")

    install_gemfile <<-G
      source "https://gem.repo1"
      git "#{lib_path("has_submodule-1.0")}" do
        gem "has_submodule"
      end
    G
    expect(err).to be_empty

    expect(the_bundle).to include_gems "has_submodule 1.0"
    expect(the_bundle).to_not include_gems "submodule 1.0"
  end

  it "handles implicit updates when modifying the source info" do
    git = build_git "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      git "#{lib_path("foo-1.0")}" do
        gem "foo"
      end
    G

    update_git "foo"
    update_git "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      git "#{lib_path("foo-1.0")}", :ref => "#{git.ref_for("HEAD^")}" do
        gem "foo"
      end
    G

    run <<-RUBY
      require 'foo'
      puts "WIN" if FOO_PREV_REF == '#{git.ref_for("HEAD^^")}'
    RUBY

    expect(out).to eq("WIN")
  end

  it "does not to a remote fetch if the revision is cached locally" do
    build_git "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => "#{lib_path("foo-1.0")}"
    G

    FileUtils.rm_r(lib_path("foo-1.0"))

    bundle "install"
    expect(out).not_to match(/updating/i)
  end

  it "doesn't blow up if bundle install is run twice in a row" do
    build_git "foo"

    gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => "#{lib_path("foo-1.0")}"
    G

    bundle "install"
    bundle "install"
  end

  it "prints a friendly error if a file blocks the git repo" do
    build_git "foo"

    FileUtils.mkdir_p(default_bundle_path)
    FileUtils.touch(default_bundle_path("bundler"))

    install_gemfile <<-G, raise_on_error: false
      source "https://gem.repo1"
      gem "foo", :git => "#{lib_path("foo-1.0")}"
    G

    expect(last_command).to be_failure
    expect(err).to include("Bundler could not install a gem because it " \
                           "needs to create a directory, but a file exists " \
                           "- #{default_bundle_path("bundler")}")
  end

  it "does not duplicate git gem sources" do
    build_lib "foo", path: lib_path("nested/foo")
    build_lib "bar", path: lib_path("nested/bar")

    build_git "foo", path: lib_path("nested")
    build_git "bar", path: lib_path("nested")

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :git => "#{lib_path("nested")}"
      gem "bar", :git => "#{lib_path("nested")}"
    G

    expect(File.read(bundled_app_lock).scan("GIT").size).to eq(1)
  end

  describe "switching sources" do
    it "doesn't explode when switching Path to Git sources" do
      build_gem "foo", "1.0", to_system: true do |s|
        s.write "lib/foo.rb", "raise 'fail'"
      end
      build_lib "foo", "1.0", path: lib_path("bar/foo")
      build_git "bar", "1.0", path: lib_path("bar") do |s|
        s.add_dependency "foo"
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "bar", :path => "#{lib_path("bar")}"
      G

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "bar", :git => "#{lib_path("bar")}"
      G

      expect(the_bundle).to include_gems "foo 1.0", "bar 1.0"
    end

    it "doesn't explode when switching Gem to Git source" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack-obama"
        gem "myrack", "1.0.0"
      G

      build_git "myrack", "1.0" do |s|
        s.write "lib/new_file.rb", "puts 'USING GIT'"
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack-obama"
        gem "myrack", "1.0.0", :git => "#{lib_path("myrack-1.0")}"
      G

      run "require 'new_file'"
      expect(out).to eq("USING GIT")
    end

    it "doesn't explode when removing an explicit exact version from a git gem with dependencies" do
      build_lib "activesupport", "7.1.4", path: lib_path("rails/activesupport")
      build_git "rails", "7.1.4", path: lib_path("rails") do |s|
        s.add_dependency "activesupport", "= 7.1.4"
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rails", "7.1.4", :git => "#{lib_path("rails")}"
      G

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rails", :git => "#{lib_path("rails")}"
      G

      expect(the_bundle).to include_gem "rails 7.1.4", "activesupport 7.1.4"
    end
  end

  describe "bundle install after the remote has been updated" do
    it "installs" do
      build_git "valim"

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "valim", :git => "#{lib_path("valim-1.0")}"
      G

      old_revision = revision_for(lib_path("valim-1.0"))
      update_git "valim"
      new_revision = revision_for(lib_path("valim-1.0"))

      old_lockfile = File.read(bundled_app_lock)
      lockfile(bundled_app_lock, old_lockfile.gsub(/revision: #{old_revision}/, "revision: #{new_revision}"))

      bundle "install"

      run <<-R
        require "valim"
        puts VALIM_PREV_REF
      R

      expect(out).to eq(old_revision)
    end

    it "gives a helpful error message when the remote ref no longer exists" do
      build_git "foo"
      revision = revision_for(lib_path("foo-1.0"))

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}", :ref => "#{revision}"
      G
      expect(out).to_not match(/Revision.*does not exist/)

      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}", :ref => "deadbeef"
      G
      expect(err).to include("Revision deadbeef does not exist in the repository")
    end

    it "gives a helpful error message when the remote branch no longer exists" do
      build_git "foo"

      install_gemfile <<-G, env: { "LANG" => "en" }, raise_on_error: false
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}", :branch => "deadbeef"
      G

      expect(err).to include("Revision deadbeef does not exist in the repository")
    end
  end

  describe "bundle install with deployment mode configured and git sources" do
    it "works" do
      build_git "valim", path: lib_path("valim")

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "valim", "= 1.0", :git => "#{lib_path("valim")}"
      G

      pristine_system_gems :bundler

      bundle "config set --local deployment true"
      bundle :install
    end
  end

  describe "gem install hooks" do
    it "runs pre-install hooks" do
      build_git "foo"
      gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      File.open(lib_path("install_hooks.rb"), "w") do |h|
        h.write <<-H
          Gem.pre_install_hooks << lambda do |inst|
            STDERR.puts "Ran pre-install hook: \#{inst.spec.full_name}"
          end
        H
      end

      bundle :install,
        requires: [lib_path("install_hooks.rb")]
      expect(err_without_deprecations).to eq("Ran pre-install hook: foo-1.0")
    end

    it "runs post-install hooks" do
      build_git "foo"
      gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      File.open(lib_path("install_hooks.rb"), "w") do |h|
        h.write <<-H
          Gem.post_install_hooks << lambda do |inst|
            STDERR.puts "Ran post-install hook: \#{inst.spec.full_name}"
          end
        H
      end

      bundle :install,
        requires: [lib_path("install_hooks.rb")]
      expect(err_without_deprecations).to eq("Ran post-install hook: foo-1.0")
    end

    it "complains if the install hook fails" do
      build_git "foo"
      gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      File.open(lib_path("install_hooks.rb"), "w") do |h|
        h.write <<-H
          Gem.pre_install_hooks << lambda do |inst|
            false
          end
        H
      end

      bundle :install, requires: [lib_path("install_hooks.rb")], raise_on_error: false
      expect(err).to include("failed for foo-1.0")
    end
  end

  context "with an extension" do
    it "installs the extension" do
      build_git "foo" do |s|
        s.add_dependency "rake"
        s.extensions << "Rakefile"
        s.write "Rakefile", <<-RUBY
          task :default do
            path = File.expand_path("lib", __dir__)
            FileUtils.mkdir_p(path)
            File.open("\#{path}/foo.rb", "w") do |f|
              f.puts "FOO = 'YES'"
            end
          end
        RUBY
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      run <<-R
        require 'foo'
        puts FOO
      R
      expect(out).to eq("YES")

      run <<-R
        puts $:.grep(/ext/)
      R
      expect(out).to include(Pathname.glob(default_bundle_path("bundler/gems/extensions/**/foo-1.0-*")).first.to_s)
    end

    it "does not use old extension after ref changes" do
      git_reader = build_git "foo", no_default: true do |s|
        s.extensions = ["ext/extconf.rb"]
        s.write "ext/extconf.rb", <<-RUBY
          require "mkmf"
          create_makefile("foo")
        RUBY
        s.write "ext/foo.c", "void Init_foo() {}"
      end

      2.times do |i|
        File.open(git_reader.path.join("ext/foo.c"), "w") do |file|
          file.write <<-C
            #include "ruby.h"
            VALUE foo() { return INT2FIX(#{i}); }
            void Init_foo() { rb_define_global_function("foo", &foo, 0); }
          C
        end
        git("commit -m \"commit for iteration #{i}\" ext/foo.c", git_reader.path)

        git_commit_sha = git_reader.ref_for("HEAD")

        install_gemfile <<-G
          source "https://gem.repo1"
          gem "foo", :git => "#{lib_path("foo-1.0")}", :ref => "#{git_commit_sha}"
        G

        run <<-R
          require 'foo'
          puts foo
        R

        expect(out).to eq(i.to_s)
      end
    end

    it "does not prompt to gem install if extension fails" do
      build_git "foo" do |s|
        s.add_dependency "rake"
        s.extensions << "Rakefile"
        s.write "Rakefile", <<-RUBY
          task :default do
            raise
          end
        RUBY
      end

      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      expect(err).to end_with(<<-M.strip)
An error occurred while installing foo (1.0), and Bundler cannot continue.

In Gemfile:
  foo
      M
      expect(out).not_to include("gem install foo")
    end

    it "does not reinstall the extension" do
      build_git "foo" do |s|
        s.add_dependency "rake"
        s.extensions << "Rakefile"
        s.write "Rakefile", <<-RUBY
          task :default do
            path = File.expand_path("lib", __dir__)
            FileUtils.mkdir_p(path)
            cur_time = Time.now.to_f.to_s
            File.open("\#{path}/foo.rb", "w") do |f|
              f.puts "FOO = \#{cur_time}"
            end
          end
        RUBY
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      run <<-R
        require 'foo'
        puts FOO
      R

      installed_time = out
      expect(installed_time).to match(/\A\d+\.\d+\z/)

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      run <<-R
        require 'foo'
        puts FOO
      R
      expect(out).to eq(installed_time)
    end

    it "does not reinstall the extension when changing another gem" do
      build_git "foo" do |s|
        s.add_dependency "rake"
        s.extensions << "Rakefile"
        s.write "Rakefile", <<-RUBY
          task :default do
            path = File.expand_path("lib", __dir__)
            FileUtils.mkdir_p(path)
            cur_time = Time.now.to_f.to_s
            File.open("\#{path}/foo.rb", "w") do |f|
              f.puts "FOO = \#{cur_time}"
            end
          end
        RUBY
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", "0.9.1"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      run <<-R
        require 'foo'
        puts FOO
      R

      installed_time = out
      expect(installed_time).to match(/\A\d+\.\d+\z/)

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack", "1.0.0"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      run <<-R
        require 'foo'
        puts FOO
      R
      expect(out).to eq(installed_time)
    end

    it "does reinstall the extension when changing refs" do
      build_git "foo" do |s|
        s.add_dependency "rake"
        s.extensions << "Rakefile"
        s.write "Rakefile", <<-RUBY
          task :default do
            path = File.expand_path("lib", __dir__)
            FileUtils.mkdir_p(path)
            cur_time = Time.now.to_f.to_s
            File.open("\#{path}/foo.rb", "w") do |f|
              f.puts "FOO = \#{cur_time}"
            end
          end
        RUBY
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      run <<-R
        require 'foo'
        puts FOO
      R

      installed_time = out

      update_git("foo", branch: "branch2")

      expect(installed_time).to match(/\A\d+\.\d+\z/)

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}", :branch => "branch2"
      G

      run <<-R
        require 'foo'
        puts FOO
      R
      expect(out).not_to eq(installed_time)

      installed_time = out

      update_git("foo")
      bundle "update foo"

      run <<-R
        require 'foo'
        puts FOO
      R
      expect(out).not_to eq(installed_time)
    end
  end

  it "ignores git environment variables" do
    build_git "xxxxxx" do |s|
      s.executables = "xxxxxxbar"
    end

    Bundler::SharedHelpers.with_clean_git_env do
      ENV["GIT_DIR"]       = "bar"
      ENV["GIT_WORK_TREE"] = "bar"

      install_gemfile <<-G
        source "https://gem.repo1"
        git "#{lib_path("xxxxxx-1.0")}" do
          gem 'xxxxxx'
        end
      G

      expect(ENV["GIT_DIR"]).to eq("bar")
      expect(ENV["GIT_WORK_TREE"]).to eq("bar")
    end
  end

  describe "without git installed" do
    it "prints a better error message when installing" do
      gemfile <<-G
        source "https://gem.repo1"

        gem "rake", git: "https://github.com/ruby/rake"
      G

      lockfile <<-L
        GIT
          remote: https://github.com/ruby/rake
          revision: 5c60da8644a9e4f655e819252e3b6ca77f42b7af
          specs:
            rake (13.0.6)

        GEM
          remote: https://rubygems.org/
          specs:

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          rake!

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      with_path_as("") do
        bundle "install", raise_on_error: false
      end
      expect(err).
        to include("You need to install git to be able to use gems from git repositories. For help installing git, please refer to GitHub's tutorial at https://help.github.com/articles/set-up-git")
    end

    it "prints a better error message when updating" do
      build_git "foo"

      install_gemfile <<-G
        source "https://gem.repo1"
        git "#{lib_path("foo-1.0")}" do
          gem 'foo'
        end
      G

      with_path_as("") do
        bundle "update", all: true, raise_on_error: false
      end
      expect(err).
        to include("You need to install git to be able to use gems from git repositories. For help installing git, please refer to GitHub's tutorial at https://help.github.com/articles/set-up-git")
    end

    it "doesn't need git in the new machine if an installed git gem is copied to another machine" do
      build_git "foo"

      install_gemfile <<-G
        source "https://gem.repo1"
        git "#{lib_path("foo-1.0")}" do
          gem 'foo'
        end
      G
      bundle "config set --global path vendor/bundle"
      bundle :install
      pristine_system_gems :bundler

      bundle "install", env: { "PATH" => "" }
      expect(out).to_not include("You need to install git to be able to use gems from git repositories.")
    end
  end

  describe "when the git source is overridden with a local git repo" do
    before do
      bundle "config set --global local.foo #{lib_path("foo")}"
    end

    describe "and git output is colorized" do
      before do
        File.open("#{ENV["HOME"]}/.gitconfig", "w") do |f|
          f.write("[color]\n\tui = always\n")
        end
      end

      it "installs successfully" do
        build_git "foo", "1.0", path: lib_path("foo")

        gemfile <<-G
          source "https://gem.repo1"
          gem "foo", :git => "#{lib_path("foo")}", :branch => "main"
        G

        bundle :install
        expect(the_bundle).to include_gems "foo 1.0"
      end
    end
  end

  context "git sources that include credentials" do
    context "that are username and password" do
      let(:credentials) { "user1:password1" }

      it "does not display the password" do
        install_gemfile <<-G, raise_on_error: false
          source "https://gem.repo1"
          git "https://#{credentials}@github.com/company/private-repo" do
            gem "foo"
          end
        G

        expect(last_command.stdboth).to_not include("password1")
        expect(out).to include("Fetching https://user1@github.com/company/private-repo")
      end
    end

    context "that is an oauth token" do
      let(:credentials) { "oauth_token" }

      it "displays the oauth scheme but not the oauth token" do
        install_gemfile <<-G, raise_on_error: false
          source "https://gem.repo1"
          git "https://#{credentials}:x-oauth-basic@github.com/company/private-repo" do
            gem "foo"
          end
        G

        expect(last_command.stdboth).to_not include("oauth_token")
        expect(out).to include("Fetching https://x-oauth-basic@github.com/company/private-repo")
      end
    end
  end
end
