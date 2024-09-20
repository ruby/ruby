# frozen_string_literal: true

RSpec.describe "Running bin/* commands" do
  before :each do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G
  end

  it "runs the bundled command when in the bundle" do
    bundle "binstubs myrack"

    build_gem "myrack", "2.0", to_system: true do |s|
      s.executables = "myrackup"
    end

    gembin "myrackup"
    expect(out).to eq("1.0.0")
  end

  it "allows the location of the gem stubs to be specified" do
    bundle "binstubs myrack", path: "gbin"

    expect(bundled_app("bin")).not_to exist
    expect(bundled_app("gbin/myrackup")).to exist

    gembin bundled_app("gbin/myrackup")
    expect(out).to eq("1.0.0")
  end

  it "allows absolute paths as a specification of where to install bin stubs" do
    bundle "binstubs myrack", path: tmp("bin")

    gembin tmp("bin/myrackup")
    expect(out).to eq("1.0.0")
  end

  it "uses the default ruby install name when shebang is not specified" do
    bundle "binstubs myrack"
    expect(File.readlines(bundled_app("bin/myrackup")).first).to eq("#!/usr/bin/env #{RbConfig::CONFIG["ruby_install_name"]}\n")
  end

  it "allows the name of the shebang executable to be specified" do
    bundle "binstubs myrack", shebang: "ruby-foo"
    expect(File.readlines(bundled_app("bin/myrackup")).first).to eq("#!/usr/bin/env ruby-foo\n")
  end

  it "runs the bundled command when out of the bundle" do
    bundle "binstubs myrack"

    build_gem "myrack", "2.0", to_system: true do |s|
      s.executables = "myrackup"
    end

    gembin "myrackup", dir: tmp
    expect(out).to eq("1.0.0")
  end

  it "works with gems in path" do
    build_lib "myrack", path: lib_path("myrack") do |s|
      s.executables = "myrackup"
    end

    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack", :path => "#{lib_path("myrack")}"
    G

    bundle "binstubs myrack"

    build_gem "myrack", "2.0", to_system: true do |s|
      s.executables = "myrackup"
    end

    gembin "myrackup"
    expect(out).to eq("1.0")
  end

  it "creates a bundle binstub" do
    gemfile <<-G
      source "https://gem.repo1"
      gem "bundler"
    G

    bundle "binstubs bundler"

    expect(bundled_app("bin/bundle")).to exist
  end

  it "does not generate bin stubs if the option was not specified" do
    bundle "install"

    expect(bundled_app("bin/myrackup")).not_to exist
  end

  it "allows you to stop installing binstubs", bundler: "< 3" do
    skip "delete permission error" if Gem.win_platform?

    bundle "install --binstubs bin/"
    bundled_app("bin/myrackup").rmtree
    bundle "install --binstubs \"\""

    expect(bundled_app("bin/myrackup")).not_to exist

    bundle "config bin"
    expect(out).to include("You have not configured a value for `bin`")
  end

  it "remembers that the option was specified", bundler: "< 3" do
    gemfile <<-G
      source "https://gem.repo1"
      gem "activesupport"
    G

    bundle :install, binstubs: "bin"

    gemfile <<-G
      source "https://gem.repo1"
      gem "activesupport"
      gem "myrack"
    G

    bundle "install"

    expect(bundled_app("bin/myrackup")).to exist
  end

  it "rewrites bins on binstubs (to maintain backwards compatibility)" do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G

    create_file("bin/myrackup", "OMG")

    bundle "binstubs myrack"

    expect(bundled_app("bin/myrackup").read).to_not eq("OMG")
  end

  it "use BUNDLE_GEMFILE gemfile for binstub" do
    # context with bin/bundler w/ default Gemfile
    bundle "binstubs bundler"

    # generate other Gemfile with executable gem
    build_repo2 do
      build_gem("bindir") {|s| s.executables = "foo" }
    end

    gemfile("OtherGemfile", <<-G)
      source "https://gem.repo2"
      gem 'bindir'
    G

    # generate binstub for executable from non default Gemfile (other then bin/bundler version)
    ENV["BUNDLE_GEMFILE"] = "OtherGemfile"
    bundle "install"
    bundle "binstubs bindir"

    # remove user settings
    ENV["BUNDLE_GEMFILE"] = nil

    # run binstub for non default Gemfile
    gembin "foo"

    expect(out).to eq("1.0")
  end
end
