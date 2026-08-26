# frozen_string_literal: true

RSpec.describe "bundle install with git sources" do
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

    it "doesn't explode when adding an explicit ref to a git gem with dependencies" do
      lib_root = lib_path("rails")

      build_lib "activesupport", "7.1.4", path: lib_root.join("activesupport")
      build_git "rails", "7.1.4", path: lib_root do |s|
        s.add_dependency "activesupport", "= 7.1.4"
      end

      old_revision = revision_for(lib_root)
      update_git "rails", "7.1.4", path: lib_root

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rails", "7.1.4", :git => "#{lib_root}"
      G

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rails", :git => "#{lib_root}", :ref => "#{old_revision}"
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

      pristine_system_gems

      bundle_config "deployment true"
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
            VALUE foo(VALUE self) { return INT2FIX(#{i}); }
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
      bundle_config_global "path vendor/bundle"
      bundle :install
      pristine_system_gems

      bundle "install", env: { "PATH" => "" }
      expect(out).to_not include("You need to install git to be able to use gems from git repositories.")
    end
  end

  describe "when the git source is overridden with a local git repo" do
    before do
      bundle_config_global "local.foo #{lib_path("foo")}"
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

        expect(stdboth).to_not include("password1")
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

        expect(stdboth).to_not include("oauth_token")
        expect(out).to include("Fetching https://x-oauth-basic@github.com/company/private-repo")
      end
    end
  end
end
