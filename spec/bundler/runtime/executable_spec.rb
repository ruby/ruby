# frozen_string_literal: true

RSpec.describe "Running bin/* commands" do
  before :each do
    install_gemfile! <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G
  end

  it "runs the bundled command when in the bundle" do
    bundle! "binstubs rack"

    build_gem "rack", "2.0", :to_system => true do |s|
      s.executables = "rackup"
    end

    gembin "rackup"
    expect(out).to eq("1.0.0")
  end

  it "allows the location of the gem stubs to be specified" do
    bundle! "binstubs rack", :path => "gbin"

    expect(bundled_app("bin")).not_to exist
    expect(bundled_app("gbin/rackup")).to exist

    gembin bundled_app("gbin/rackup")
    expect(out).to eq("1.0.0")
  end

  it "allows absolute paths as a specification of where to install bin stubs" do
    bundle! "binstubs rack", :path => tmp("bin")

    gembin tmp("bin/rackup")
    expect(out).to eq("1.0.0")
  end

  it "uses the default ruby install name when shebang is not specified" do
    bundle! "binstubs rack"
    expect(File.open("bin/rackup").gets).to eq("#!/usr/bin/env #{RbConfig::CONFIG["ruby_install_name"]}\n")
  end

  it "allows the name of the shebang executable to be specified" do
    bundle! "binstubs rack", :shebang => "ruby-foo"
    expect(File.open("bin/rackup").gets).to eq("#!/usr/bin/env ruby-foo\n")
  end

  it "runs the bundled command when out of the bundle" do
    bundle! "binstubs rack"

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

    bundle! "binstubs rack"

    build_gem "rack", "2.0", :to_system => true do |s|
      s.executables = "rackup"
    end

    gembin "rackup"
    expect(out).to eq("1.0")
  end

  it "creates a bundle binstub" do
    build_gem "bundler", Bundler::VERSION, :to_system => true do |s|
      s.executables = "bundle"
    end

    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "bundler"
    G

    bundle! "binstubs bundler"

    expect(bundled_app("bin/bundle")).to exist
  end

  it "does not generate bin stubs if the option was not specified" do
    bundle! "install"

    expect(bundled_app("bin/rackup")).not_to exist
  end

  it "allows you to stop installing binstubs", :bundler => "< 3" do
    bundle! "install --binstubs bin/"
    bundled_app("bin/rackup").rmtree
    bundle! "install --binstubs \"\""

    expect(bundled_app("bin/rackup")).not_to exist

    bundle! "config bin"
    expect(out).to include("You have not configured a value for `bin`")
  end

  it "remembers that the option was specified", :bundler => "< 3" do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "activesupport"
    G

    bundle! :install, forgotten_command_line_options([:binstubs, :bin] => "bin")

    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "activesupport"
      gem "rack"
    G

    bundle "install"

    expect(bundled_app("bin/rackup")).to exist
  end

  it "rewrites bins on --binstubs (to maintain backwards compatibility)", :bundler => "< 2" do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G

    bundle! :install, forgotten_command_line_options([:binstubs, :bin] => "bin")

    File.open(bundled_app("bin/rackup"), "wb") do |file|
      file.print "OMG"
    end

    bundle "install"

    expect(bundled_app("bin/rackup").read).to_not eq("OMG")
  end

  it "rewrites bins on binstubs (to maintain backwards compatibility)" do
    install_gemfile! <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G

    create_file("bin/rackup", "OMG")

    bundle! "binstubs rack"

    expect(bundled_app("bin/rackup").read).to_not eq("OMG")
  end

  it "use BUNDLE_GEMFILE gemfile for binstub" do
    # context with bin/bunlder w/ default Gemfile
    bundle! "binstubs bundler"

    # generate other Gemfile with executable gem
    build_repo2 do
      build_gem("bindir") {|s| s.executables = "foo" }
    end

    create_file("OtherGemfile", <<-G)
      source "file://#{gem_repo2}"
      gem 'bindir'
    G

    # generate binstub for executable from non default Gemfile (other then bin/bundler version)
    ENV["BUNDLE_GEMFILE"] = "OtherGemfile"
    bundle "install"
    bundle! "binstubs bindir"

    # remove user settings
    ENV["BUNDLE_GEMFILE"] = nil

    # run binstub for non default Gemfile
    gembin "foo"

    expect(exitstatus).to eq(0) if exitstatus
    expect(out).to eq("1.0")
  end
end
