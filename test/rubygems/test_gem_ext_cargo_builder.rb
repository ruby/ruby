# frozen_string_literal: true
require_relative 'helper'
require 'rubygems/ext'

class TestGemExtCargoBuilder < Gem::TestCase
  def setup
    super

    @rust_envs = {
      'CARGO_HOME' => File.join(@orig_env['HOME'], '.cargo'),
      'RUSTUP_HOME' => File.join(@orig_env['HOME'], '.rustup'),
    }

    system(@rust_envs, 'cargo', '-V', out: IO::NULL, err: [:child, :out])
    pend 'cargo not present' unless $?.success?
  end

  def setup_rust_gem(name)
    @ext = File.join(@tempdir, 'ext')
    @dest_path = File.join(@tempdir, 'prefix')
    @fixture_dir = Pathname.new(File.expand_path("test_gem_ext_cargo_builder/#{name}/", __dir__))

    FileUtils.mkdir_p @dest_path
    FileUtils.cp_r(@fixture_dir.to_s, @ext)
  end

  def test_build_staticlib
    skip_unsupported_platforms!
    setup_rust_gem "rust_ruby_example"

    content = @fixture_dir.join('Cargo.toml').read.gsub("cdylib", "staticlib")
    File.write(File.join(@ext, 'Cargo.toml'), content)

    output = []

    Dir.chdir @ext do
      ENV.update(@rust_envs)
      spec = Gem::Specification.new 'rust_ruby_example', '0.1.0'
      builder = Gem::Ext::CargoBuilder.new(spec)
      assert_raise(Gem::Ext::CargoBuilder::DylibNotFoundError) do
        builder.build nil, @dest_path, output
      end
    end
  end

  def test_build_cdylib
    skip_unsupported_platforms!
    setup_rust_gem "rust_ruby_example"

    output = []

    Dir.chdir @ext do
      ENV.update(@rust_envs)
      spec = Gem::Specification.new 'rust_ruby_example', '0.1.0'
      builder = Gem::Ext::CargoBuilder.new(spec)
      builder.build nil, @dest_path, output
    end

    output = output.join "\n"

    bundle = File.join(@dest_path, "release/rust_ruby_example.#{RbConfig::CONFIG['DLEXT']}")

    require(bundle)

    assert_match RustRubyExample.reverse('hello'), 'olleh'

    assert_match "Compiling rust_ruby_example v0.1.0", output
    assert_match "Finished release [optimized] target(s)", output
  rescue Exception => e
    pp output if output

    raise(e)
  end

  def test_build_fail
    skip_unsupported_platforms!
    setup_rust_gem "rust_ruby_example"

    output = []

    FileUtils.rm(File.join(@ext, 'src/lib.rs'))

    error = assert_raise(Gem::InstallError) do
      Dir.chdir @ext do
        ENV.update(@rust_envs)
        spec = Gem::Specification.new 'rust_ruby_example', '0.1.0'
        builder = Gem::Ext::CargoBuilder.new(spec)
        builder.build nil, @dest_path, output
      end
    end

    output = output.join "\n"

    assert_match 'cargo failed', error.message
  end

  def test_full_integration
    skip_unsupported_platforms!
    setup_rust_gem "rust_ruby_example"

    Dir.chdir @ext do
      require 'tmpdir'

      gem = [@rust_envs, *ruby_with_rubygems_in_load_path, File.expand_path('../../bin/gem', __dir__)]

      Dir.mktmpdir("rust_ruby_example") do |dir|
        built_gem = File.expand_path(File.join(dir, "rust_ruby_example.gem"))
        Open3.capture2e(*gem, "build", "rust_ruby_example.gemspec", "--output", built_gem)
        Open3.capture2e(*gem, "install", "--verbose", "--local", built_gem, *ARGV)
      end

      stdout_and_stderr_str, status = Open3.capture2e(@rust_envs, *ruby_with_rubygems_in_load_path, "-rrust_ruby_example", "-e", "puts 'Result: ' + RustRubyExample.reverse('hello world')")

      assert status.success?, stdout_and_stderr_str
      assert_match "Result: #{"hello world".reverse}", stdout_and_stderr_str
    end
  end

  def test_custom_name
    skip_unsupported_platforms!
    setup_rust_gem "custom_name"

    Dir.chdir @ext do
      require 'tmpdir'

      gem = [@rust_envs, *ruby_with_rubygems_in_load_path, File.expand_path('../../bin/gem', __dir__)]

      Dir.mktmpdir("custom_name") do |dir|
        built_gem = File.expand_path(File.join(dir, "custom_name.gem"))
        Open3.capture2e(*gem, "build", "custom_name.gemspec", "--output", built_gem)
        Open3.capture2e(*gem, "install", "--verbose", "--local", built_gem, *ARGV)
      end

      stdout_and_stderr_str, status = Open3.capture2e(@rust_envs, *ruby_with_rubygems_in_load_path, "-rcustom_name", "-e", "puts 'Result: ' + CustomName.say_hello")

      assert status.success?, stdout_and_stderr_str
      assert_match "Result: Hello world!", stdout_and_stderr_str
    end
  end

  def skip_unsupported_platforms!
    pend "jruby not supported" if java_platform?
    pend "truffleruby not supported (yet)" if RUBY_ENGINE == 'truffleruby'
    pend "mswin not supported (yet)" if /mswin/ =~ RUBY_PLATFORM && ENV.key?('GITHUB_ACTIONS')
    pend "ruby.h is not provided by ruby repo" if testing_ruby_repo?
  end
end
