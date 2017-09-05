# frozen_string_literal: true
require "spec_helper"

RSpec.describe "bundle install with git sources" do
  describe "when floating on master" do
    before :each do
      build_git "foo" do |s|
        s.executables = "foobar"
      end

      install_gemfile <<-G
        source "file://#{gem_repo1}"
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

    it "caches the git repo" do
      expect(Dir["#{default_bundle_path}/cache/bundler/git/foo-1.0-*"].size).to eq(1)
    end

    it "caches the evaluated gemspec" do
      git = update_git "foo" do |s|
        s.executables = ["foobar"] # we added this the first time, so keep it now
        s.files = ["bin/foobar"] # updating git nukes the files list
        foospec = s.to_ruby.gsub(/s\.files.*/, 's.files = `git ls-files -z`.split("\x0")')
        s.write "foo.gemspec", foospec
      end

      bundle "update foo"

      sha = git.ref_for("master", 11)
      spec_file = default_bundle_path.join("bundler/gems/foo-1.0-#{sha}/foo.gemspec").to_s
      ruby_code = Gem::Specification.load(spec_file).to_ruby
      file_code = File.read(spec_file)
      expect(file_code).to eq(ruby_code)
    end

    it "does not update the git source implicitly" do
      update_git "foo"

      in_app_root2 do
        install_gemfile bundled_app2("Gemfile"), <<-G
          git "#{lib_path("foo-1.0")}" do
            gem 'foo'
          end
        G
      end

      in_app_root do
        run <<-RUBY
          require 'foo'
          puts "fail" if defined?(FOO_PREV_REF)
        RUBY

        expect(out).to be_empty
      end
    end

    it "sets up git gem executables on the path" do
      bundle "exec foobar"
      expect(out).to eq("1.0")
    end

    it "complains if pinned specs don't exist in the git repo" do
      build_git "foo"

      install_gemfile <<-G
        gem "foo", "1.1", :git => "#{lib_path("foo-1.0")}"
      G

      expect(out).to include("Source contains 'foo' at: 1.0 ruby")
    end

    it "complains with version and platform if pinned specs don't exist in the git repo" do
      simulate_platform "java"

      build_git "only_java" do |s|
        s.platform = "java"
      end

      install_gemfile <<-G
        platforms :jruby do
          gem "only_java", "1.2", :git => "#{lib_path("only_java-1.0-java")}"
        end
      G

      expect(out).to include("Source contains 'only_java' at: 1.0 java")
    end

    it "complains with multiple versions and platforms if pinned specs don't exist in the git repo" do
      simulate_platform "java"

      build_git "only_java", "1.0" do |s|
        s.platform = "java"
      end

      build_git "only_java", "1.1" do |s|
        s.platform = "java"
        s.write "only_java1-0.gemspec", File.read("#{lib_path("only_java-1.0-java")}/only_java.gemspec")
      end

      install_gemfile <<-G
        platforms :jruby do
          gem "only_java", "1.2", :git => "#{lib_path("only_java-1.1-java")}"
        end
      G

      expect(out).to include("Source contains 'only_java' at: 1.0 java, 1.1 java")
    end

    it "still works after moving the application directory" do
      bundle "install --path vendor/bundle"
      FileUtils.mv bundled_app, tmp("bundled_app.bck")

      Dir.chdir tmp("bundled_app.bck")
      expect(the_bundle).to include_gems "foo 1.0"
    end

    it "can still install after moving the application directory" do
      bundle "install --path vendor/bundle"
      FileUtils.mv bundled_app, tmp("bundled_app.bck")

      update_git "foo", "1.1", :path => lib_path("foo-1.0")

      Dir.chdir tmp("bundled_app.bck")
      gemfile tmp("bundled_app.bck/Gemfile"), <<-G
        source "file://#{gem_repo1}"
        git "#{lib_path("foo-1.0")}" do
          gem 'foo'
        end

        gem "rack", "1.0"
      G

      bundle "update foo"

      expect(the_bundle).to include_gems "foo 1.1", "rack 1.0"
    end
  end

  describe "with an empty git block" do
    before do
      build_git "foo"
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"

        git "#{lib_path("foo-1.0")}" do
          # this page left intentionally blank
        end
      G
    end

    it "does not explode" do
      bundle "install"
      expect(the_bundle).to include_gems "rack 1.0"
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
        git "#{lib_path("foo-1.0")}", :ref => "#{@revision}" do
          gem "foo"
        end
      G

      run <<-RUBY
        require 'foo'
        puts "WIN" unless defined?(FOO_PREV_REF)
      RUBY

      expect(out).to eq("WIN")
    end

    it "works when the revision is a symbol" do
      install_gemfile <<-G
        git "#{lib_path("foo-1.0")}", :ref => #{@revision.to_sym.inspect} do
          gem "foo"
        end
      G
      expect(err).to lack_errors

      run <<-RUBY
        require 'foo'
        puts "WIN" unless defined?(FOO_PREV_REF)
      RUBY

      expect(out).to eq("WIN")
    end
  end

  describe "when specifying a branch" do
    let(:branch) { "branch" }
    let(:repo) { build_git("foo").path }
    before(:each) do
      update_git("foo", :path => repo, :branch => branch)
    end

    it "works" do
      install_gemfile <<-G
        git "#{repo}", :branch => #{branch.dump} do
          gem "foo"
        end
      G

      expect(the_bundle).to include_gems("foo 1.0")
    end

    context "when the branch starts with a `#`" do
      let(:branch) { "#149/redirect-url-fragment" }
      it "works" do
        install_gemfile <<-G
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
        install_gemfile <<-G
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
    before(:each) do
      update_git("foo", :path => repo, :tag => tag)
    end

    it "works" do
      install_gemfile <<-G
        git "#{repo}", :tag => #{tag.dump} do
          gem "foo"
        end
      G

      expect(the_bundle).to include_gems("foo 1.0")
    end

    context "when the tag starts with a `#`" do
      let(:tag) { "#149/redirect-url-fragment" }
      it "works" do
        install_gemfile <<-G
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
        install_gemfile <<-G
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
      # We don't generate it because we actually don't need it
      # build_git "rack", "0.8"

      build_git "rack", "0.8", :path => lib_path("local-rack") do |s|
        s.write "lib/rack.rb", "puts :LOCAL"
      end

      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-0.8")}", :branch => "master"
      G

      bundle %(config local.rack #{lib_path("local-rack")})
      bundle :install
      expect(out).to match(/at #{lib_path('local-rack')}/)

      run "require 'rack'"
      expect(out).to eq("LOCAL")
    end

    it "chooses the local repository on runtime" do
      build_git "rack", "0.8"

      FileUtils.cp_r("#{lib_path("rack-0.8")}/.", lib_path("local-rack"))

      update_git "rack", "0.8", :path => lib_path("local-rack") do |s|
        s.write "lib/rack.rb", "puts :LOCAL"
      end

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-0.8")}", :branch => "master"
      G

      bundle %(config local.rack #{lib_path("local-rack")})
      run "require 'rack'"
      expect(out).to eq("LOCAL")
    end

    it "unlocks the source when the dependencies have changed while switching to the local" do
      build_git "rack", "0.8"

      FileUtils.cp_r("#{lib_path("rack-0.8")}/.", lib_path("local-rack"))

      update_git "rack", "0.8", :path => lib_path("local-rack") do |s|
        s.write "rack.gemspec", build_spec("rack", "0.8") { runtime "rspec", "> 0" }.first.to_ruby
        s.write "lib/rack.rb", "puts :LOCAL"
      end

      install_gemfile! <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-0.8")}", :branch => "master"
      G

      bundle! %(config local.rack #{lib_path("local-rack")})
      bundle! :install
      run! "require 'rack'"
      expect(out).to eq("LOCAL")
    end

    it "updates specs on runtime" do
      system_gems "nokogiri-1.4.2"

      build_git "rack", "0.8"

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-0.8")}", :branch => "master"
      G

      lockfile0 = File.read(bundled_app("Gemfile.lock"))

      FileUtils.cp_r("#{lib_path("rack-0.8")}/.", lib_path("local-rack"))
      update_git "rack", "0.8", :path => lib_path("local-rack") do |s|
        s.add_dependency "nokogiri", "1.4.2"
      end

      bundle %(config local.rack #{lib_path("local-rack")})
      run "require 'rack'"

      lockfile1 = File.read(bundled_app("Gemfile.lock"))
      expect(lockfile1).not_to eq(lockfile0)
    end

    it "updates ref on install" do
      build_git "rack", "0.8"

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-0.8")}", :branch => "master"
      G

      lockfile0 = File.read(bundled_app("Gemfile.lock"))

      FileUtils.cp_r("#{lib_path("rack-0.8")}/.", lib_path("local-rack"))
      update_git "rack", "0.8", :path => lib_path("local-rack")

      bundle %(config local.rack #{lib_path("local-rack")})
      bundle :install

      lockfile1 = File.read(bundled_app("Gemfile.lock"))
      expect(lockfile1).not_to eq(lockfile0)
    end

    it "explodes if given path does not exist on install" do
      build_git "rack", "0.8"

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-0.8")}", :branch => "master"
      G

      bundle %(config local.rack #{lib_path("local-rack")})
      bundle :install
      expect(out).to match(/Cannot use local override for rack-0.8 because #{Regexp.escape(lib_path('local-rack').to_s)} does not exist/)
    end

    it "explodes if branch is not given on install" do
      build_git "rack", "0.8"
      FileUtils.cp_r("#{lib_path("rack-0.8")}/.", lib_path("local-rack"))

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-0.8")}"
      G

      bundle %(config local.rack #{lib_path("local-rack")})
      bundle :install
      expect(out).to match(/cannot use local override/i)
    end

    it "does not explode if disable_local_branch_check is given" do
      build_git "rack", "0.8"
      FileUtils.cp_r("#{lib_path("rack-0.8")}/.", lib_path("local-rack"))

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-0.8")}"
      G

      bundle %(config local.rack #{lib_path("local-rack")})
      bundle %(config disable_local_branch_check true)
      bundle :install
      expect(out).to match(/Bundle complete!/)
    end

    it "explodes on different branches on install" do
      build_git "rack", "0.8"

      FileUtils.cp_r("#{lib_path("rack-0.8")}/.", lib_path("local-rack"))

      update_git "rack", "0.8", :path => lib_path("local-rack"), :branch => "another" do |s|
        s.write "lib/rack.rb", "puts :LOCAL"
      end

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-0.8")}", :branch => "master"
      G

      bundle %(config local.rack #{lib_path("local-rack")})
      bundle :install
      expect(out).to match(/is using branch another but Gemfile specifies master/)
    end

    it "explodes on invalid revision on install" do
      build_git "rack", "0.8"

      build_git "rack", "0.8", :path => lib_path("local-rack") do |s|
        s.write "lib/rack.rb", "puts :LOCAL"
      end

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-0.8")}", :branch => "master"
      G

      bundle %(config local.rack #{lib_path("local-rack")})
      bundle :install
      expect(out).to match(/The Gemfile lock is pointing to revision \w+/)
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
      build_git "rack", "0.8"

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-0.8")}"
      G

      expect(the_bundle).to include_gems "rack 0.8"
    end

    it "installs dependencies from git even if a newer gem is available elsewhere" do
      system_gems "rack-1.0.0"

      build_lib "rack", "1.0", :path => lib_path("nested/bar") do |s|
        s.write "lib/rack.rb", "puts 'WIN OVERRIDE'"
      end

      build_git "foo", :path => lib_path("nested") do |s|
        s.add_dependency "rack", "= 1.0"
      end

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "foo", :git => "#{lib_path("nested")}"
      G

      run "require 'rack'"
      expect(out).to eq("WIN OVERRIDE")
    end

    it "correctly unlocks when changing to a git source" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", "0.9.1"
      G

      build_git "rack", :path => lib_path("rack")

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", "1.0.0", :git => "#{lib_path("rack")}"
      G

      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "correctly unlocks when changing to a git source without versions" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      build_git "rack", "1.2", :path => lib_path("rack")

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack")}"
      G

      expect(the_bundle).to include_gems "rack 1.2"
    end
  end

  describe "block syntax" do
    it "pulls all gems from a git block" do
      build_lib "omg", :path => lib_path("hi2u/omg")
      build_lib "hi2u", :path => lib_path("hi2u")

      install_gemfile <<-G
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
      source "file://#{gem_repo1}"
      gem "foo", :git => "#{lib_path("foo-1.0")}"
      gem "rails", "2.3.2"
    G

    expect(the_bundle).to include_gems "foo 1.0"
    expect(the_bundle).to include_gems "rails 2.3.2"
  end

  it "runs the gemspec in the context of its parent directory" do
    build_lib "bar", :path => lib_path("foo/bar"), :gemspec => false do |s|
      s.write lib_path("foo/bar/lib/version.rb"), %(BAR_VERSION = '1.0')
      s.write "bar.gemspec", <<-G
        $:.unshift Dir.pwd # For 1.9
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

    build_git "foo", :path => lib_path("foo") do |s|
      s.write "bin/foo", ""
    end

    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "bar", :git => "#{lib_path("foo")}"
      gem "rails", "2.3.2"
    G

    expect(the_bundle).to include_gems "bar 1.0"
    expect(the_bundle).to include_gems "rails 2.3.2"
  end

  it "installs from git even if a rubygems gem is present" do
    build_gem "foo", "1.0", :path => lib_path("fake_foo"), :to_system => true do |s|
      s.write "lib/foo.rb", "raise 'FAIL'"
    end

    build_git "foo", "1.0"

    install_gemfile <<-G
      gem "foo", "1.0", :git => "#{lib_path("foo-1.0")}"
    G

    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "fakes the gem out if there is no gemspec" do
    build_git "foo", :gemspec => false

    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "foo", "1.0", :git => "#{lib_path("foo-1.0")}"
      gem "rails", "2.3.2"
    G

    expect(the_bundle).to include_gems("foo 1.0")
    expect(the_bundle).to include_gems("rails 2.3.2")
  end

  it "catches git errors and spits out useful output" do
    gemfile <<-G
      gem "foo", "1.0", :git => "omgomg"
    G

    bundle :install

    expect(out).to include("Git error:")
    expect(err).to include("fatal")
    expect(err).to include("omgomg")
  end

  it "works when the gem path has spaces in it" do
    build_git "foo", :path => lib_path("foo space-1.0")

    install_gemfile <<-G
      gem "foo", :git => "#{lib_path("foo space-1.0")}"
    G

    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "handles repos that have been force-pushed" do
    build_git "forced", "1.0"

    install_gemfile <<-G
      git "#{lib_path("forced-1.0")}" do
        gem 'forced'
      end
    G
    expect(the_bundle).to include_gems "forced 1.0"

    update_git "forced" do |s|
      s.write "lib/forced.rb", "FORCED = '1.1'"
    end

    bundle "update"
    expect(the_bundle).to include_gems "forced 1.1"

    Dir.chdir(lib_path("forced-1.0")) do
      `git reset --hard HEAD^`
    end

    bundle "update"
    expect(the_bundle).to include_gems "forced 1.0"
  end

  it "ignores submodules if :submodule is not passed" do
    build_git "submodule", "1.0"
    build_git "has_submodule", "1.0" do |s|
      s.add_dependency "submodule"
    end
    Dir.chdir(lib_path("has_submodule-1.0")) do
      sys_exec "git submodule add #{lib_path("submodule-1.0")} submodule-1.0"
      `git commit -m "submodulator"`
    end

    install_gemfile <<-G
      git "#{lib_path("has_submodule-1.0")}" do
        gem "has_submodule"
      end
    G
    expect(out).to match(/could not find gem 'submodule/i)

    expect(the_bundle).not_to include_gems "has_submodule 1.0"
  end

  it "handles repos with submodules" do
    build_git "submodule", "1.0"
    build_git "has_submodule", "1.0" do |s|
      s.add_dependency "submodule"
    end
    Dir.chdir(lib_path("has_submodule-1.0")) do
      sys_exec "git submodule add #{lib_path("submodule-1.0")} submodule-1.0"
      `git commit -m "submodulator"`
    end

    install_gemfile <<-G
      git "#{lib_path("has_submodule-1.0")}", :submodules => true do
        gem "has_submodule"
      end
    G

    expect(the_bundle).to include_gems "has_submodule 1.0"
  end

  it "handles implicit updates when modifying the source info" do
    git = build_git "foo"

    install_gemfile <<-G
      git "#{lib_path("foo-1.0")}" do
        gem "foo"
      end
    G

    update_git "foo"
    update_git "foo"

    install_gemfile <<-G
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
      gem "foo", :git => "#{lib_path("foo-1.0")}"
    G

    FileUtils.rm_rf(lib_path("foo-1.0"))

    bundle "install"
    expect(out).not_to match(/updating/i)
  end

  it "doesn't blow up if bundle install is run twice in a row" do
    build_git "foo"

    gemfile <<-G
      gem "foo", :git => "#{lib_path("foo-1.0")}"
    G

    bundle "install"
    bundle "install"
    expect(exitstatus).to eq(0) if exitstatus
  end

  it "prints a friendly error if a file blocks the git repo" do
    build_git "foo"

    FileUtils.touch(default_bundle_path("bundler"))

    install_gemfile <<-G
      gem "foo", :git => "#{lib_path("foo-1.0")}"
    G

    expect(exitstatus).to_not eq(0) if exitstatus
    expect(out).to include("Bundler could not install a gem because it " \
                           "needs to create a directory, but a file exists " \
                           "- #{default_bundle_path("bundler")}")
  end

  it "does not duplicate git gem sources" do
    build_lib "foo", :path => lib_path("nested/foo")
    build_lib "bar", :path => lib_path("nested/bar")

    build_git "foo", :path => lib_path("nested")
    build_git "bar", :path => lib_path("nested")

    gemfile <<-G
      gem "foo", :git => "#{lib_path("nested")}"
      gem "bar", :git => "#{lib_path("nested")}"
    G

    bundle "install"
    expect(File.read(bundled_app("Gemfile.lock")).scan("GIT").size).to eq(1)
  end

  describe "switching sources" do
    it "doesn't explode when switching Path to Git sources" do
      build_gem "foo", "1.0", :to_system => true do |s|
        s.write "lib/foo.rb", "raise 'fail'"
      end
      build_lib "foo", "1.0", :path => lib_path("bar/foo")
      build_git "bar", "1.0", :path => lib_path("bar") do |s|
        s.add_dependency "foo"
      end

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "bar", :path => "#{lib_path("bar")}"
      G

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "bar", :git => "#{lib_path("bar")}"
      G

      expect(the_bundle).to include_gems "foo 1.0", "bar 1.0"
    end

    it "doesn't explode when switching Gem to Git source" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack-obama"
        gem "rack", "1.0.0"
      G

      build_git "rack", "1.0" do |s|
        s.write "lib/new_file.rb", "puts 'USING GIT'"
      end

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack-obama"
        gem "rack", "1.0.0", :git => "#{lib_path("rack-1.0")}"
      G

      run "require 'new_file'"
      expect(out).to eq("USING GIT")
    end
  end

  describe "bundle install after the remote has been updated" do
    it "installs" do
      build_git "valim"

      install_gemfile <<-G
        gem "valim", :git => "file://#{lib_path("valim-1.0")}"
      G

      old_revision = revision_for(lib_path("valim-1.0"))
      update_git "valim"
      new_revision = revision_for(lib_path("valim-1.0"))

      lockfile = File.read(bundled_app("Gemfile.lock"))
      File.open(bundled_app("Gemfile.lock"), "w") do |file|
        file.puts lockfile.gsub(/revision: #{old_revision}/, "revision: #{new_revision}")
      end

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
        gem "foo", :git => "file://#{lib_path("foo-1.0")}", :ref => "#{revision}"
      G
      bundle "install"
      expect(out).to_not match(/Revision.*does not exist/)

      install_gemfile <<-G
        gem "foo", :git => "file://#{lib_path("foo-1.0")}", :ref => "deadbeef"
      G
      bundle "install"
      expect(out).to include("Revision deadbeef does not exist in the repository")
    end
  end

  describe "bundle install --deployment with git sources" do
    it "works" do
      build_git "valim", :path => lib_path("valim")

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "valim", "= 1.0", :git => "#{lib_path("valim")}"
      G

      simulate_new_machine

      bundle "install --deployment"
      expect(exitstatus).to eq(0) if exitstatus
    end
  end

  describe "gem install hooks" do
    it "runs pre-install hooks" do
      build_git "foo"
      gemfile <<-G
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      File.open(lib_path("install_hooks.rb"), "w") do |h|
        h.write <<-H
          require 'rubygems'
          Gem.pre_install_hooks << lambda do |inst|
            STDERR.puts "Ran pre-install hook: \#{inst.spec.full_name}"
          end
        H
      end

      bundle :install,
        :requires => [lib_path("install_hooks.rb")]
      expect(err).to eq_err("Ran pre-install hook: foo-1.0")
    end

    it "runs post-install hooks" do
      build_git "foo"
      gemfile <<-G
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      File.open(lib_path("install_hooks.rb"), "w") do |h|
        h.write <<-H
          require 'rubygems'
          Gem.post_install_hooks << lambda do |inst|
            STDERR.puts "Ran post-install hook: \#{inst.spec.full_name}"
          end
        H
      end

      bundle :install,
        :requires => [lib_path("install_hooks.rb")]
      expect(err).to eq_err("Ran post-install hook: foo-1.0")
    end

    it "complains if the install hook fails" do
      build_git "foo"
      gemfile <<-G
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      File.open(lib_path("install_hooks.rb"), "w") do |h|
        h.write <<-H
          require 'rubygems'
          Gem.pre_install_hooks << lambda do |inst|
            false
          end
        H
      end

      bundle :install,
        :requires => [lib_path("install_hooks.rb")]
      expect(out).to include("failed for foo-1.0")
    end
  end

  context "with an extension" do
    it "installs the extension", :ruby_repo do
      build_git "foo" do |s|
        s.add_dependency "rake"
        s.extensions << "Rakefile"
        s.write "Rakefile", <<-RUBY
          task :default do
            path = File.expand_path("../lib", __FILE__)
            FileUtils.mkdir_p(path)
            File.open("\#{path}/foo.rb", "w") do |f|
              f.puts "FOO = 'YES'"
            end
          end
        RUBY
      end

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      run <<-R
        require 'foo'
        puts FOO
      R
      expect(out).to eq("YES")

      run! <<-R
        puts $:.grep(/ext/)
      R
      expect(out).to eq(Pathname.glob(system_gem_path("bundler/gems/extensions/**/foo-1.0-*")).first.to_s)
    end

    it "does not use old extension after ref changes", :ruby_repo do
      git_reader = build_git "foo", :no_default => true do |s|
        s.extensions = ["ext/extconf.rb"]
        s.write "ext/extconf.rb", <<-RUBY
          require "mkmf"
          create_makefile("foo")
        RUBY
        s.write "ext/foo.c", "void Init_foo() {}"
      end

      2.times do |i|
        Dir.chdir(git_reader.path) do
          File.open("ext/foo.c", "w") do |file|
            file.write <<-C
              #include "ruby.h"
              VALUE foo() { return INT2FIX(#{i}); }
              void Init_foo() { rb_define_global_function("foo", &foo, 0); }
            C
          end
          `git commit -m 'commit for iteration #{i}' ext/foo.c`
        end
        git_sha = git_reader.ref_for("HEAD")

        install_gemfile <<-G
          source "file://#{gem_repo1}"
          gem "foo", :git => "#{lib_path("foo-1.0")}", :ref => "#{git_sha}"
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

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      expect(out).to end_with(<<-M.strip)
An error occurred while installing foo (1.0), and Bundler cannot continue.

In Gemfile:
  foo
      M
      expect(out).not_to include("gem install foo")
    end

    it "does not reinstall the extension", :ruby_repo, :rubygems => ">= 2.3.0" do
      build_git "foo" do |s|
        s.add_dependency "rake"
        s.extensions << "Rakefile"
        s.write "Rakefile", <<-RUBY
          task :default do
            path = File.expand_path("../lib", __FILE__)
            FileUtils.mkdir_p(path)
            cur_time = Time.now.to_f.to_s
            File.open("\#{path}/foo.rb", "w") do |f|
              f.puts "FOO = \#{cur_time}"
            end
          end
        RUBY
      end

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      run! <<-R
        require 'foo'
        puts FOO
      R

      installed_time = out
      expect(installed_time).to match(/\A\d+\.\d+\z/)

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      run! <<-R
        require 'foo'
        puts FOO
      R
      expect(out).to eq(installed_time)
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
        source "file://#{gem_repo1}"
        git "#{lib_path("xxxxxx-1.0")}" do
          gem 'xxxxxx'
        end
      G

      expect(exitstatus).to eq(0) if exitstatus
      expect(ENV["GIT_DIR"]).to eq("bar")
      expect(ENV["GIT_WORK_TREE"]).to eq("bar")
    end
  end

  describe "without git installed" do
    it "prints a better error message" do
      build_git "foo"

      install_gemfile <<-G
        git "#{lib_path("foo-1.0")}" do
          gem 'foo'
        end
      G

      with_path_as("") do
        bundle "update"
      end
      expect(out).to include("You need to install git to be able to use gems from git repositories. For help installing git, please refer to GitHub's tutorial at https://help.github.com/articles/set-up-git")
    end

    it "installs a packaged git gem successfully" do
      build_git "foo"

      install_gemfile <<-G
        git "#{lib_path("foo-1.0")}" do
          gem 'foo'
        end
      G
      bundle "package --all"
      simulate_new_machine

      bundle "install", :env => { "PATH" => "" }
      expect(out).to_not include("You need to install git to be able to use gems from git repositories.")
      expect(exitstatus).to be_zero if exitstatus
    end
  end

  describe "when the git source is overriden with a local git repo" do
    before do
      bundle "config --global local.foo #{lib_path("foo")}"
    end

    describe "and git output is colorized" do
      before do
        File.open("#{ENV["HOME"]}/.gitconfig", "w") do |f|
          f.write("[color]\n\tui = always\n")
        end
      end

      it "installs successfully" do
        build_git "foo", "1.0", :path => lib_path("foo")

        gemfile <<-G
          gem "foo", :git => "#{lib_path("foo")}", :branch => "master"
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
        install_gemfile <<-G
          git "https://#{credentials}@github.com/company/private-repo" do
            gem "foo"
          end
        G

        bundle :install
        expect(out).to_not include("password1")
        expect(err).to_not include("password1")
        expect(out).to include("Fetching https://user1@github.com/company/private-repo")
      end
    end

    context "that is an oauth token" do
      let(:credentials) { "oauth_token" }

      it "displays the oauth scheme but not the oauth token" do
        install_gemfile <<-G
          git "https://#{credentials}:x-oauth-basic@github.com/company/private-repo" do
            gem "foo"
          end
        G

        bundle :install
        expect(out).to_not include("oauth_token")
        expect(err).to_not include("oauth_token")
        expect(out).to include("Fetching https://x-oauth-basic@github.com/company/private-repo")
      end
    end
  end
end
