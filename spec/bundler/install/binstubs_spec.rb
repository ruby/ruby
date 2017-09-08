# frozen_string_literal: true
require "spec_helper"

RSpec.describe "bundle install" do
  describe "when system_bindir is set" do
    # On OS X, Gem.bindir defaults to /usr/bin, so system_bindir is useful if
    # you want to avoid sudo installs for system gems with OS X's default ruby
    it "overrides Gem.bindir" do
      expect(Pathname.new("/usr/bin")).not_to be_writable unless Process.euid == 0
      gemfile <<-G
        require 'rubygems'
        def Gem.bindir; "/usr/bin"; end
        source "file://#{gem_repo1}"
        gem "rack"
      G

      config "BUNDLE_SYSTEM_BINDIR" => system_gem_path("altbin").to_s
      bundle :install
      expect(the_bundle).to include_gems "rack 1.0.0"
      expect(system_gem_path("altbin/rackup")).to exist
    end
  end

  describe "when multiple gems contain the same exe" do
    before do
      build_repo2 do
        build_gem "fake", "14" do |s|
          s.executables = "rackup"
        end
      end

      install_gemfile <<-G, :binstubs => true
        source "file://#{gem_repo2}"
        gem "fake"
        gem "rack"
      G
    end

    it "prints a deprecation notice" do
      bundle "config major_deprecations true"
      gembin("rackup")
      expect(out).to include("Bundler is using a binstub that was created for a different gem.")
    end

    it "loads the correct spec's executable" do
      gembin("rackup")
      expect(out).to eq("1.2")
    end
  end
end
