# frozen_string_literal: true
require "spec_helper"

%w(cache package).each do |cmd|
  RSpec.describe "bundle #{cmd} with path" do
    it "is no-op when the path is within the bundle" do
      build_lib "foo", :path => bundled_app("lib/foo")

      install_gemfile <<-G
        gem "foo", :path => '#{bundled_app("lib/foo")}'
      G

      bundle "#{cmd} --all"
      expect(bundled_app("vendor/cache/foo-1.0")).not_to exist
      expect(the_bundle).to include_gems "foo 1.0"
    end

    it "copies when the path is outside the bundle " do
      build_lib "foo"

      install_gemfile <<-G
        gem "foo", :path => '#{lib_path("foo-1.0")}'
      G

      bundle "#{cmd} --all"
      expect(bundled_app("vendor/cache/foo-1.0")).to exist
      expect(bundled_app("vendor/cache/foo-1.0/.bundlecache")).to be_file

      FileUtils.rm_rf lib_path("foo-1.0")
      expect(the_bundle).to include_gems "foo 1.0"
    end

    it "copies when the path is outside the bundle and the paths intersect" do
      libname = File.basename(Dir.pwd) + "_gem"
      libpath = File.join(File.dirname(Dir.pwd), libname)

      build_lib libname, :path => libpath

      install_gemfile <<-G
        gem "#{libname}", :path => '#{libpath}'
      G

      bundle "#{cmd} --all"
      expect(bundled_app("vendor/cache/#{libname}")).to exist
      expect(bundled_app("vendor/cache/#{libname}/.bundlecache")).to be_file

      FileUtils.rm_rf libpath
      expect(the_bundle).to include_gems "#{libname} 1.0"
    end

    it "updates the path on each cache" do
      build_lib "foo"

      install_gemfile <<-G
        gem "foo", :path => '#{lib_path("foo-1.0")}'
      G

      bundle "#{cmd} --all"

      build_lib "foo" do |s|
        s.write "lib/foo.rb", "puts :CACHE"
      end

      bundle "#{cmd} --all"

      expect(bundled_app("vendor/cache/foo-1.0")).to exist
      FileUtils.rm_rf lib_path("foo-1.0")

      run "require 'foo'"
      expect(out).to eq("CACHE")
    end

    it "removes stale entries cache" do
      build_lib "foo"

      install_gemfile <<-G
        gem "foo", :path => '#{lib_path("foo-1.0")}'
      G

      bundle "#{cmd} --all"

      install_gemfile <<-G
        gem "bar", :path => '#{lib_path("bar-1.0")}'
      G

      bundle "#{cmd} --all"
      expect(bundled_app("vendor/cache/bar-1.0")).not_to exist
    end

    it "raises a warning without --all" do
      build_lib "foo"

      install_gemfile <<-G
        gem "foo", :path => '#{lib_path("foo-1.0")}'
      G

      bundle cmd
      expect(out).to match(/please pass the \-\-all flag/)
      expect(bundled_app("vendor/cache/foo-1.0")).not_to exist
    end

    it "stores the given flag" do
      build_lib "foo"

      install_gemfile <<-G
        gem "foo", :path => '#{lib_path("foo-1.0")}'
      G

      bundle "#{cmd} --all"
      build_lib "bar"

      install_gemfile <<-G
        gem "foo", :path => '#{lib_path("foo-1.0")}'
        gem "bar", :path => '#{lib_path("bar-1.0")}'
      G

      bundle cmd
      expect(bundled_app("vendor/cache/bar-1.0")).to exist
    end

    it "can rewind chosen configuration" do
      build_lib "foo"

      install_gemfile <<-G
        gem "foo", :path => '#{lib_path("foo-1.0")}'
      G

      bundle "#{cmd} --all"
      build_lib "baz"

      gemfile <<-G
        gem "foo", :path => '#{lib_path("foo-1.0")}'
        gem "baz", :path => '#{lib_path("baz-1.0")}'
      G

      bundle "#{cmd} --no-all"
      expect(bundled_app("vendor/cache/baz-1.0")).not_to exist
    end
  end
end
