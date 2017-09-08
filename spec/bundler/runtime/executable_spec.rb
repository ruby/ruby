# frozen_string_literal: true
require "spec_helper"

RSpec.describe "Running bin/* commands" do
  before :each do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G
  end

  it "runs the bundled command when in the bundle" do
    bundle "install --binstubs"

    build_gem "rack", "2.0", :to_system => true do |s|
      s.executables = "rackup"
    end

    gembin "rackup"
    expect(out).to eq("1.0.0")
  end

  it "allows the location of the gem stubs to be specified" do
    bundle "install --binstubs gbin"

    expect(bundled_app("bin")).not_to exist
    expect(bundled_app("gbin/rackup")).to exist

    gembin bundled_app("gbin/rackup")
    expect(out).to eq("1.0.0")
  end

  it "allows absolute paths as a specification of where to install bin stubs" do
    bundle "install --binstubs #{tmp}/bin"

    gembin tmp("bin/rackup")
    expect(out).to eq("1.0.0")
  end

  it "uses the default ruby install name when shebang is not specified" do
    bundle "install --binstubs"
    expect(File.open("bin/rackup").gets).to eq("#!/usr/bin/env #{RbConfig::CONFIG["ruby_install_name"]}\n")
  end

  it "allows the name of the shebang executable to be specified" do
    bundle "install --binstubs --shebang ruby-foo"
    expect(File.open("bin/rackup").gets).to eq("#!/usr/bin/env ruby-foo\n")
  end

  it "runs the bundled command when out of the bundle" do
    bundle "install --binstubs"

    build_gem "rack", "2.0", :to_system => true do |s|
      s.executables = "rackup"
    end

    Dir.chdir(tmp) do
      gembin "rackup"
      expect(out).to eq("1.0.0")
    end
  end

  it "works with gems in path" do
    build_lib "rack", :path => lib_path("rack") do |s|
      s.executables = "rackup"
    end

    gemfile <<-G
      gem "rack", :path => "#{lib_path("rack")}"
    G

    bundle "install --binstubs"

    build_gem "rack", "2.0", :to_system => true do |s|
      s.executables = "rackup"
    end

    gembin "rackup"
    expect(out).to eq("1.0")
  end

  it "don't bundle da bundla" do
    build_gem "bundler", Bundler::VERSION, :to_system => true do |s|
      s.executables = "bundle"
    end

    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "bundler"
    G

    bundle "install --binstubs"

    expect(bundled_app("bin/bundle")).not_to exist
  end

  it "does not generate bin stubs if the option was not specified" do
    bundle "install"

    expect(bundled_app("bin/rackup")).not_to exist
  end

  it "allows you to stop installing binstubs" do
    bundle "install --binstubs bin/"
    bundled_app("bin/rackup").rmtree
    bundle "install --binstubs \"\""

    expect(bundled_app("bin/rackup")).not_to exist

    bundle "config bin"
    expect(out).to include("You have not configured a value for `bin`")
  end

  it "remembers that the option was specified" do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "activesupport"
    G

    bundle "install --binstubs"

    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "activesupport"
      gem "rack"
    G

    bundle "install"

    expect(bundled_app("bin/rackup")).to exist
  end

  it "rewrites bins on --binstubs (to maintain backwards compatibility)" do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G

    bundle "install --binstubs bin/"

    File.open(bundled_app("bin/rackup"), "wb") do |file|
      file.print "OMG"
    end

    bundle "install"

    expect(bundled_app("bin/rackup").read).to_not eq("OMG")
  end
end
