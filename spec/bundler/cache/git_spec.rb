# frozen_string_literal: true

RSpec.describe "git base name" do
  it "base_name should strip private repo uris" do
    source = Bundler::Source::Git.new("uri" => "git@github.com:bundler.git")
    expect(source.send(:base_name)).to eq("bundler")
  end

  it "base_name should strip network share paths" do
    source = Bundler::Source::Git.new("uri" => "//MachineName/ShareFolder")
    expect(source.send(:base_name)).to eq("ShareFolder")
  end
end

RSpec.describe "bundle cache with git" do
  it "copies repository to vendor cache and uses it" do
    git = build_git "foo"
    ref = git.ref_for("main", 11)

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G

    bundle "config set cache_all true"
    bundle :cache
    expect(bundled_app("vendor/cache/foo-1.0-#{ref}")).to exist
    expect(bundled_app("vendor/cache/foo-1.0-#{ref}/.git")).not_to exist
    expect(bundled_app("vendor/cache/foo-1.0-#{ref}/.bundlecache")).to be_file

    FileUtils.rm_rf lib_path("foo-1.0")
    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "copies repository to vendor cache and uses it even when configured with `path`" do
    git = build_git "foo"
    ref = git.ref_for("main", 11)

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G

    bundle "config set --local path vendor/bundle"
    bundle "install"
    bundle "config set cache_all true"
    bundle :cache

    expect(bundled_app("vendor/cache/foo-1.0-#{ref}")).to exist
    expect(bundled_app("vendor/cache/foo-1.0-#{ref}/.git")).not_to exist

    FileUtils.rm_rf lib_path("foo-1.0")
    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "runs twice without exploding" do
    build_git "foo"

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G

    bundle "config set cache_all true"
    bundle :cache
    bundle :cache

    expect(out).to include "Updating files in vendor/cache"
    FileUtils.rm_rf lib_path("foo-1.0")
    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "tracks updates" do
    git = build_git "foo"
    old_ref = git.ref_for("main", 11)

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G

    bundle "config set cache_all true"
    bundle :cache

    update_git "foo" do |s|
      s.write "lib/foo.rb", "puts :CACHE"
    end

    ref = git.ref_for("main", 11)
    expect(ref).not_to eq(old_ref)

    bundle "update", :all => true
    bundle "config set cache_all true"
    bundle :cache

    expect(bundled_app("vendor/cache/foo-1.0-#{ref}")).to exist
    expect(bundled_app("vendor/cache/foo-1.0-#{old_ref}")).not_to exist

    FileUtils.rm_rf lib_path("foo-1.0")
    run "require 'foo'"
    expect(out).to eq("CACHE")
  end

  it "tracks updates when specifying the gem" do
    git = build_git "foo"
    old_ref = git.ref_for("main", 11)

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G

    bundle "config set cache_all true"
    bundle :cache

    update_git "foo" do |s|
      s.write "lib/foo.rb", "puts :CACHE"
    end

    ref = git.ref_for("main", 11)
    expect(ref).not_to eq(old_ref)

    bundle "update foo"

    expect(bundled_app("vendor/cache/foo-1.0-#{ref}")).to exist
    expect(bundled_app("vendor/cache/foo-1.0-#{old_ref}")).not_to exist

    FileUtils.rm_rf lib_path("foo-1.0")
    run "require 'foo'"
    expect(out).to eq("CACHE")
  end

  it "uses the local repository to generate the cache" do
    git = build_git "foo"
    ref = git.ref_for("main", 11)

    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "foo", :git => '#{lib_path("foo-invalid")}', :branch => :main
    G

    bundle %(config set local.foo #{lib_path("foo-1.0")})
    bundle "install"
    bundle "config set cache_all true"
    bundle :cache

    expect(bundled_app("vendor/cache/foo-invalid-#{ref}")).to exist

    # Updating the local still uses the local.
    update_git "foo" do |s|
      s.write "lib/foo.rb", "puts :LOCAL"
    end

    run "require 'foo'"
    expect(out).to eq("LOCAL")
  end

  it "copies repository to vendor cache, including submodules" do
    # CVE-2022-39253: https://lore.kernel.org/lkml/xmqq4jw1uku5.fsf@gitster.g/
    system(*%W[git config --global protocol.file.allow always])

    build_git "submodule", "1.0"

    git = build_git "has_submodule", "1.0" do |s|
      s.add_dependency "submodule"
    end

    sys_exec "git submodule add #{lib_path("submodule-1.0")} submodule-1.0", :dir => lib_path("has_submodule-1.0")
    sys_exec "git commit -m \"submodulator\"", :dir => lib_path("has_submodule-1.0")

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      git "#{lib_path("has_submodule-1.0")}", :submodules => true do
        gem "has_submodule"
      end
    G

    ref = git.ref_for("main", 11)
    bundle "config set cache_all true"
    bundle :cache

    expect(bundled_app("vendor/cache/has_submodule-1.0-#{ref}")).to exist
    expect(bundled_app("vendor/cache/has_submodule-1.0-#{ref}/submodule-1.0")).to exist
    expect(the_bundle).to include_gems "has_submodule 1.0"
  end

  it "caches pre-evaluated gemspecs" do
    git = build_git "foo"

    # Insert a gemspec method that shells out
    spec_lines = lib_path("foo-1.0/foo.gemspec").read.split("\n")
    spec_lines.insert(-2, "s.description = `echo bob`")
    update_git("foo") {|s| s.write "foo.gemspec", spec_lines.join("\n") }

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G
    bundle "config set cache_all true"
    bundle :cache

    ref = git.ref_for("main", 11)
    gemspec = bundled_app("vendor/cache/foo-1.0-#{ref}/foo.gemspec").read
    expect(gemspec).to_not match("`echo bob`")
  end

  it "can install after bundle cache with git not installed" do
    build_git "foo"

    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "foo", :git => '#{lib_path("foo-1.0")}'
    G
    bundle "config set cache_all true"
    bundle :cache, "all-platforms" => true, :install => false

    simulate_new_machine
    with_path_as "" do
      bundle "config set deployment true"
      bundle :install, :local => true
      expect(the_bundle).to include_gem "foo 1.0"
    end
  end
end
