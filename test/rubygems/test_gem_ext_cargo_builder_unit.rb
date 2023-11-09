# frozen_string_literal: true

require_relative "helper"
require "rubygems/ext"

class TestGemExtCargoBuilderUnit < Gem::TestCase
  def test_cargo_command_passes_args
    skip_unsupported_platforms!
    builder = Gem::Ext::CargoBuilder.new
    command = builder.cargo_command(Dir.pwd, @tempdir, ["--all-features"])

    assert_includes command, "--all-features"
  end

  def test_cargo_command_locks_in_release_profile
    skip_unsupported_platforms!
    builder = Gem::Ext::CargoBuilder.new
    builder.profile = :release
    command = builder.cargo_command(Dir.pwd, @tempdir)

    assert_includes command, "--locked"
  end

  def test_cargo_command_passes_respects_cargo_env_var
    skip_unsupported_platforms!
    old_cargo = ENV["CARGO"]
    ENV["CARGO"] = "mycargo"
    builder = Gem::Ext::CargoBuilder.new
    command = builder.cargo_command(Dir.pwd, @tempdir)

    assert_includes command, "mycargo"
  ensure
    ENV["CARGO"] = old_cargo
  end

  def test_build_env_includes_rbconfig
    skip_unsupported_platforms!
    builder = Gem::Ext::CargoBuilder.new
    env = builder.build_env

    assert_equal env.fetch("RBCONFIG_RUBY_SO_NAME"), RbConfig::CONFIG["RUBY_SO_NAME"]
  end

  def test_cargo_command_passes_respects_cargo_build_target
    skip_unsupported_platforms!
    old_cargo = ENV["CARGO_BUILD_TARGET"]
    ENV["CARGO_BUILD_TARGET"] = "x86_64-unknown-linux-gnu"
    builder = Gem::Ext::CargoBuilder.new
    command = builder.cargo_command(Dir.pwd, @tempdir, ["--locked"])

    assert_includes command, "--target"
    assert_includes command, "x86_64-unknown-linux-gnu"
  ensure
    ENV["CARGO_BUILD_TARGET"] = old_cargo
  end

  def skip_unsupported_platforms!
    pend "jruby not supported" if Gem.java_platform?
  end
end
