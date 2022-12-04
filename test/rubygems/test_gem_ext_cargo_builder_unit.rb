# frozen_string_literal: true

require_relative "helper"
require "rubygems/ext"

class TestGemExtCargoBuilderUnit < Gem::TestCase
  def test_cargo_command_passes_args
    skip_unsupported_platforms!
    spec = Gem::Specification.new "rust_ruby_example", "0.1.0"
    builder = Gem::Ext::CargoBuilder.new(spec)
    command = builder.cargo_command(Dir.pwd, @tempdir, ["--all-features"])

    assert_includes command, "--all-features"
  end

  def test_cargo_command_locks_in_release_profile
    skip_unsupported_platforms!
    spec = Gem::Specification.new "rust_ruby_example", "0.1.0"
    builder = Gem::Ext::CargoBuilder.new(spec)
    builder.profile = :release
    command = builder.cargo_command(Dir.pwd, @tempdir)

    assert_includes command, "--locked"
  end

  def test_cargo_command_does_not_lock_in_dev_profile
    skip_unsupported_platforms!
    spec = Gem::Specification.new "rust_ruby_example", "0.1.0"
    builder = Gem::Ext::CargoBuilder.new(spec)
    builder.profile = :dev
    command = builder.cargo_command(Dir.pwd, @tempdir)

    assert_not_includes command, "--locked"
  end

  def test_cargo_command_passes_respects_cargo_env_var
    skip_unsupported_platforms!
    old_cargo = ENV["CARGO"]
    ENV["CARGO"] = "mycargo"
    spec = Gem::Specification.new "rust_ruby_example", "0.1.0"
    builder = Gem::Ext::CargoBuilder.new(spec)
    command = builder.cargo_command(Dir.pwd, @tempdir)

    assert_includes command, "mycargo"
  ensure
    ENV["CARGO"] = old_cargo
  end

  def test_build_env_includes_rbconfig
    skip_unsupported_platforms!
    spec = Gem::Specification.new "rust_ruby_example", "0.1.0"
    builder = Gem::Ext::CargoBuilder.new(spec)
    env = builder.build_env

    assert_equal env.fetch("RBCONFIG_RUBY_SO_NAME"), RbConfig::CONFIG["RUBY_SO_NAME"]
  end

  def test_cargo_command_passes_respects_cargo_build_target
    skip_unsupported_platforms!
    old_cargo = ENV["CARGO_BUILD_TARGET"]
    ENV["CARGO_BUILD_TARGET"] = "x86_64-unknown-linux-gnu"
    spec = Gem::Specification.new "rust_ruby_example", "0.1.0"
    builder = Gem::Ext::CargoBuilder.new(spec)
    command = builder.cargo_command(Dir.pwd, @tempdir, ["--locked"])

    assert_includes command, "--target"
    assert_includes command, "x86_64-unknown-linux-gnu"
  ensure
    ENV["CARGO_BUILD_TARGET"] = old_cargo
  end

  def skip_unsupported_platforms!
    pend "jruby not supported" if java_platform?
  end
end
