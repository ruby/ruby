# frozen_string_literal: true

require_relative "helper"
require "rubygems/ext"
require "open3"

class TestGemExtCargoBuilder < Gem::TestCase
  def setup
    super

    @rust_envs = {
      "CARGO_HOME" => ENV.fetch("CARGO_HOME", File.join(@orig_env["HOME"], ".cargo")),
      "RUSTUP_HOME" => ENV.fetch("RUSTUP_HOME", File.join(@orig_env["HOME"], ".rustup")),
    }
  end

  def setup_rust_gem(name)
    @ext = File.join(@tempdir, "ext")
    @dest_path = File.join(@tempdir, "prefix")
    @fixture_dir = Pathname.new(File.expand_path("test_gem_ext_cargo_builder/#{name}/", __dir__))

    FileUtils.mkdir_p @dest_path
    FileUtils.cp_r(@fixture_dir.to_s, @ext)
  end

  def test_build_cdylib
    skip_unsupported_platforms!
    setup_rust_gem "rust_ruby_example"

    output = []

    Dir.chdir @ext do
      ENV.update(@rust_envs)
      builder = Gem::Ext::CargoBuilder.new
      builder.build "Cargo.toml", @dest_path, output
    end

    output = output.join "\n"
    bundle = File.join(@dest_path, "rust_ruby_example.#{RbConfig::CONFIG["DLEXT"]}")

    assert_match(/Finished/, output)
    assert_match(/release/, output)
    assert_ffi_handle bundle, "Init_rust_ruby_example"
  rescue StandardError => e
    pp output if output

    raise(e)
  end

  def test_rubygems_cfg_passed_to_rustc
    skip_unsupported_platforms!
    setup_rust_gem "rust_ruby_example"
    version_slug = Gem::VERSION.tr(".", "_")
    output = []

    replace_in_rust_file("src/lib.rs", "rubygems_x_x_x", "rubygems_#{version_slug}")

    Dir.chdir @ext do
      ENV.update(@rust_envs)
      builder = Gem::Ext::CargoBuilder.new
      builder.build "Cargo.toml", @dest_path, output
    end

    output = output.join "\n"
    bundle = File.join(@dest_path, "rust_ruby_example.#{RbConfig::CONFIG["DLEXT"]}")

    assert_ffi_handle bundle, "hello_from_rubygems"
    assert_ffi_handle bundle, "hello_from_rubygems_version"
    refute_ffi_handle bundle, "should_never_exist"
  rescue StandardError => e
    pp output if output

    raise(e)
  end

  def test_build_fail
    skip_unsupported_platforms!
    setup_rust_gem "rust_ruby_example"

    FileUtils.rm(File.join(@ext, "src/lib.rs"))

    error = assert_raise(Gem::InstallError) do
      Dir.chdir @ext do
        ENV.update(@rust_envs)
        builder = Gem::Ext::CargoBuilder.new
        builder.build "Cargo.toml", @dest_path, []
      end
    end

    assert_match(/cargo\s.*\sfailed/, error.message)
  end

  def test_full_integration
    skip_unsupported_platforms!
    setup_rust_gem "rust_ruby_example"

    require "open3"

    Dir.chdir @ext do
      require "tmpdir"

      env_for_subprocess = @rust_envs.merge("GEM_HOME" => Gem.paths.home)
      gem = [env_for_subprocess, *ruby_with_rubygems_in_load_path, File.expand_path("../../exe/gem", __dir__)]

      Dir.mktmpdir("rust_ruby_example") do |dir|
        built_gem = File.expand_path(File.join(dir, "rust_ruby_example.gem"))
        Open3.capture2e(*gem, "build", "rust_ruby_example.gemspec", "--output", built_gem)
        Open3.capture2e(*gem, "install", "--verbose", "--local", built_gem, *ARGV)

        stdout_and_stderr_str, status = Open3.capture2e(env_for_subprocess, *ruby_with_rubygems_in_load_path, "-rrust_ruby_example", "-e", "puts 'Result: ' + RustRubyExample.reverse('hello world')")
        assert status.success?, stdout_and_stderr_str
        assert_match "Result: #{"hello world".reverse}", stdout_and_stderr_str
      end
    end
  end

  def test_custom_name
    skip_unsupported_platforms!
    setup_rust_gem "custom_name"

    Dir.chdir @ext do
      require "tmpdir"

      env_for_subprocess = @rust_envs.merge("GEM_HOME" => Gem.paths.home)
      gem = [env_for_subprocess, *ruby_with_rubygems_in_load_path, File.expand_path("../../exe/gem", __dir__)]

      Dir.mktmpdir("custom_name") do |dir|
        built_gem = File.expand_path(File.join(dir, "custom_name.gem"))
        Open3.capture2e(*gem, "build", "custom_name.gemspec", "--output", built_gem)
        Open3.capture2e(*gem, "install", "--verbose", "--local", built_gem, *ARGV)
      end

      stdout_and_stderr_str, status = Open3.capture2e(env_for_subprocess, *ruby_with_rubygems_in_load_path, "-rcustom_name", "-e", "puts 'Result: ' + CustomName.say_hello")

      assert status.success?, stdout_and_stderr_str
      assert_match "Result: Hello world!", stdout_and_stderr_str
    end
  end

  private

  def skip_unsupported_platforms!
    pend "jruby not supported" if Gem.java_platform?
    pend "truffleruby not supported (yet)" if RUBY_ENGINE == "truffleruby"
    system(@rust_envs, "cargo", "-V", out: IO::NULL, err: [:child, :out])
    pend "cargo not present" unless $?.success?
    pend "ruby.h is not provided by ruby repo" if ruby_repo?
    pend "rust toolchain of mingw is broken" if mingw_windows?
  end

  def assert_ffi_handle(bundle, name)
    require "fiddle"
    dylib_handle = Fiddle.dlopen bundle
    assert_nothing_raised { dylib_handle[name] }
  ensure
    dylib_handle&.close
  end

  def refute_ffi_handle(bundle, name)
    require "fiddle"
    dylib_handle = Fiddle.dlopen bundle
    assert_raise { dylib_handle[name] }
  ensure
    dylib_handle&.close
  end

  def replace_in_rust_file(name, from, to)
    content = @fixture_dir.join(name).read.gsub(from, to)
    File.write(File.join(@ext, name), content)
  end
end
