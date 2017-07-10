# frozen_string_literal: true
require "spec_helper"

describe "git base name" do
  it "base_name should strip private repo uris" do
    source = Bundler::Source::Git.new("uri" => "git@github.com:bundler.git")
    expect(source.send(:base_name)).to eq("bundler")
  end

  it "base_name should strip network share paths" do
    source = Bundler::Source::Git.new("uri" => "//MachineName/ShareFolder")
    expect(source.send(:base_name)).to eq("ShareFolder")
  end
end

%w(cache package).each do |cmd|
  describe "bundle #{cmd} with git" do
    it "copies repository to vendor cache and uses it" do
      git = build_git "foo"
      ref = git.ref_for("master", 11)

      install_gemfile <<-G
        gem "foo", :git => '#{lib_path("foo-1.0")}'
      G

      bundle "#{cmd} --all"
      expect(bundled_app("vendor/cache/foo-1.0-#{ref}")).to exist
      expect(bundled_app("vendor/cache/foo-1.0-#{ref}/.git")).not_to exist
      expect(bundled_app("vendor/cache/foo-1.0-#{ref}/.bundlecache")).to be_file

      FileUtils.rm_rf lib_path("foo-1.0")
      expect(the_bundle).to include_gems "foo 1.0"
    end

    it "copies repository to vendor cache and uses it even when installed with bundle --path" do
      git = build_git "foo"
      ref = git.ref_for("master", 11)

      install_gemfile <<-G
        gem "foo", :git => '#{lib_path("foo-1.0")}'
      G

      bundle "install --path vendor/bundle"
      bundle "#{cmd} --all"

      expect(bundled_app("vendor/cache/foo-1.0-#{ref}")).to exist
      expect(bundled_app("vendor/cache/foo-1.0-#{ref}/.git")).not_to exist

      FileUtils.rm_rf lib_path("foo-1.0")
      expect(the_bundle).to include_gems "foo 1.0"
    end

    it "runs twice without exploding" do
      build_git "foo"

      install_gemfile <<-G
        gem "foo", :git => '#{lib_path("foo-1.0")}'
      G

      bundle "#{cmd} --all"
      bundle "#{cmd} --all"

      expect(err).to lack_errors
      FileUtils.rm_rf lib_path("foo-1.0")
      expect(the_bundle).to include_gems "foo 1.0"
    end

    it "tracks updates" do
      git = build_git "foo"
      old_ref = git.ref_for("master", 11)

      install_gemfile <<-G
        gem "foo", :git => '#{lib_path("foo-1.0")}'
      G

      bundle "#{cmd} --all"

      update_git "foo" do |s|
        s.write "lib/foo.rb", "puts :CACHE"
      end

      ref = git.ref_for("master", 11)
      expect(ref).not_to eq(old_ref)

      bundle "update"
      bundle "#{cmd} --all"

      expect(bundled_app("vendor/cache/foo-1.0-#{ref}")).to exist
      expect(bundled_app("vendor/cache/foo-1.0-#{old_ref}")).not_to exist

      FileUtils.rm_rf lib_path("foo-1.0")
      run "require 'foo'"
      expect(out).to eq("CACHE")
    end

    it "uses the local repository to generate the cache" do
      git = build_git "foo"
      ref = git.ref_for("master", 11)

      gemfile <<-G
        gem "foo", :git => '#{lib_path("foo-invalid")}', :branch => :master
      G

      bundle %(config local.foo #{lib_path("foo-1.0")})
      bundle "install"
      bundle "#{cmd} --all"

      expect(bundled_app("vendor/cache/foo-invalid-#{ref}")).to exist

      # Updating the local still uses the local.
      update_git "foo" do |s|
        s.write "lib/foo.rb", "puts :LOCAL"
      end

      run "require 'foo'"
      expect(out).to eq("LOCAL")
    end

    it "copies repository to vendor cache, including submodules" do
      build_git "submodule", "1.0"

      git = build_git "has_submodule", "1.0" do |s|
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

      ref = git.ref_for("master", 11)
      bundle "#{cmd} --all"

      expect(bundled_app("vendor/cache/has_submodule-1.0-#{ref}")).to exist
      expect(bundled_app("vendor/cache/has_submodule-1.0-#{ref}/submodule-1.0")).to exist
      expect(the_bundle).to include_gems "has_submodule 1.0"
    end

    it "displays warning message when detecting git repo in Gemfile" do
      build_git "foo"

      install_gemfile <<-G
        gem "foo", :git => '#{lib_path("foo-1.0")}'
      G

      bundle "#{cmd}"

      expect(out).to include("Your Gemfile contains path and git dependencies.")
    end

    it "does not display warning message if cache_all is set in bundle config" do
      build_git "foo"

      install_gemfile <<-G
        gem "foo", :git => '#{lib_path("foo-1.0")}'
      G

      bundle "#{cmd} --all"
      bundle "#{cmd}"

      expect(out).not_to include("Your Gemfile contains path and git dependencies.")
    end

    it "caches pre-evaluated gemspecs" do
      git = build_git "foo"

      # Insert a gemspec method that shells out
      spec_lines = lib_path("foo-1.0/foo.gemspec").read.split("\n")
      spec_lines.insert(-2, "s.description = `echo bob`")
      update_git("foo") {|s| s.write "foo.gemspec", spec_lines.join("\n") }

      install_gemfile <<-G
        gem "foo", :git => '#{lib_path("foo-1.0")}'
      G
      bundle "#{cmd} --all"

      ref = git.ref_for("master", 11)
      gemspec = bundled_app("vendor/cache/foo-1.0-#{ref}/foo.gemspec").read
      expect(gemspec).to_not match("`echo bob`")
    end
  end
end
