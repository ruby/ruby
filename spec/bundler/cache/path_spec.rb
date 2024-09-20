# frozen_string_literal: true

RSpec.describe "bundle cache with path" do
  it "is no-op when the path is within the bundle" do
    build_lib "foo", path: bundled_app("lib/foo")

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => '#{bundled_app("lib/foo")}'
    G

    bundle "config set cache_all true"
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

    bundle "config set cache_all true"
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

    bundle "config set cache_all true"
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

    bundle "config set cache_all true"
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

    bundle "config set cache_all true"
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

  it "does not cache path gems by default", bundler: "< 3" do
    build_lib "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => '#{lib_path("foo-1.0")}'
    G

    bundle :cache
    expect(err).to be_empty
    expect(bundled_app("vendor/cache/foo-1.0")).not_to exist
  end

  it "caches path gems by default", bundler: "3" do
    build_lib "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => '#{lib_path("foo-1.0")}'
    G

    bundle :cache
    expect(err).to be_empty
    expect(bundled_app("vendor/cache/foo-1.0")).to exist
  end

  it "stores the given flag" do
    build_lib "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => '#{lib_path("foo-1.0")}'
    G

    bundle "config set cache_all true"
    bundle :cache
    build_lib "bar"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => '#{lib_path("foo-1.0")}'
      gem "bar", :path => '#{lib_path("bar-1.0")}'
    G

    bundle :cache
    expect(bundled_app("vendor/cache/bar-1.0")).to exist
  end

  it "can rewind chosen configuration" do
    build_lib "foo"

    install_gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => '#{lib_path("foo-1.0")}'
    G

    bundle "config set cache_all true"
    bundle :cache
    build_lib "baz"

    gemfile <<-G
      source "https://gem.repo1"
      gem "foo", :path => '#{lib_path("foo-1.0")}'
      gem "baz", :path => '#{lib_path("baz-1.0")}'
    G

    bundle "cache --no-all", raise_on_error: false
    expect(bundled_app("vendor/cache/baz-1.0")).not_to exist
  end
end
