# frozen_string_literal: true

RSpec.describe "bundle cache with path" do
  it "is no-op when the path is within the bundle" do
    build_lib "foo", path: bundled_app("lib/foo")

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => '#{bundled_app("lib/foo")}'
    G

    bundle :cache
    expect(bundled_app("vendor/cache/foo-1.0")).not_to exist
    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "copies when the path is outside the bundle " do
    build_lib "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => '#{lib_path("foo-1.0")}'
    G

    bundle :cache
    expect(bundled_app("vendor/cache/foo-1.0")).to exist
    expect(bundled_app("vendor/cache/foo-1.0/.bundlecache")).to be_file

    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "copies when the path is outside the bundle and the paths intersect" do
    libname = File.basename(bundled_app) + "_gem"
    libpath = File.join(File.dirname(bundled_app), libname)

    build_lib libname, path: libpath

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "#{libname}", :path => '#{libpath}'
    G

    bundle :cache
    expect(bundled_app("vendor/cache/#{libname}")).to exist
    expect(bundled_app("vendor/cache/#{libname}/.bundlecache")).to be_file

    expect(the_bundle).to include_gems "#{libname} 1.0"
  end

  it "updates the path on each cache" do
    build_lib "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => '#{lib_path("foo-1.0")}'
    G

    bundle :cache

    build_lib "foo" do |s|
      s.write "lib/foo.rb", "puts :CACHE"
    end

    bundle :cache

    expect(bundled_app("vendor/cache/foo-1.0")).to exist

    run "require 'foo'"
    expect(out).to eq("CACHE")
  end

  it "removes stale entries cache" do
    build_lib "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => '#{lib_path("foo-1.0")}'
    G

    bundle :cache

    expect(bundled_app("vendor/cache/foo-1.0")).to exist

    build_lib "bar"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "bar", :path => '#{lib_path("bar-1.0")}'
    G

    bundle :cache
    expect(bundled_app("vendor/cache/foo-1.0")).not_to exist
  end

  it "removes stale entries whose names look like home directory expansions" do
    build_lib "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => '#{lib_path("foo-1.0")}'
    G

    bundle :cache

    tilde_entry = bundled_app("vendor/cache/~")
    # a name no account can have, so a regression cannot resolve it to a real home
    tilde_user_entry = bundled_app("vendor/cache/~nonexistent.user")
    [tilde_entry, tilde_user_entry].each do |entry|
      FileUtils.mkdir_p entry
      FileUtils.touch entry.join(".bundlecache")
    end

    bundle :cache

    expect(tilde_entry).not_to exist
    expect(tilde_user_entry).not_to exist
    expect(home).to exist
  end

  it "does not cache path gems if cache_all is set to false" do
    build_lib "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => '#{lib_path("foo-1.0")}'
    G
    bundle "config cache_all false"

    bundle :cache
    expect(err).to be_empty
    expect(bundled_app("vendor/cache/foo-1.0")).not_to exist
  end

  it "caches path gems by default" do
    build_lib "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => '#{lib_path("foo-1.0")}'
    G

    bundle :cache
    expect(err).to be_empty
    expect(bundled_app("vendor/cache/foo-1.0")).to exist
  end
end
