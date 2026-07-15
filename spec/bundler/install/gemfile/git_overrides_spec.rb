# frozen_string_literal: true

RSpec.describe "bundle install with git sources" do
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

  it "does not do a remote fetch if the revision is cached locally" do
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
end
