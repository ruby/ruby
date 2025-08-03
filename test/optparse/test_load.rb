# frozen_string_literal: false
require 'test/unit'
require 'optparse'
require 'tmpdir'

class TestOptionParserLoad < Test::Unit::TestCase
  def setup
    @tmpdir = Dir.mktmpdir("optparse_test-")
    @basename = File.basename($0, '.*')
    @envs = %w[HOME XDG_CONFIG_HOME XDG_CONFIG_DIRS].each_with_object({}) do |v, h|
      h[v] = ENV.delete(v)
    end
  end

  def teardown
    ENV.update(@envs)
    FileUtils.rm_rf(@tmpdir)
  end

  def new_parser
    @result = nil
    OptionParser.new do |opt|
      opt.on("--test=arg") {|v| @result = v}
    end
  end

  def assert_load(result)
    assert new_parser.load
    assert_equal(result, @result)
    assert new_parser.load(into: into = {})
    assert_equal({test: result}, into)
  end

  def assert_load_nothing
    assert !new_parser.load
    assert_nil @result
  end

  def setup_options(env, dir, suffix = nil)
    env.update({'HOME'=>@tmpdir})
    optdir = File.join(@tmpdir, dir)
    FileUtils.mkdir_p(optdir)
    file = File.join(optdir, [@basename, suffix].join(""))
    File.write(file, "--test=#{dir}")
    ENV.update(env)
    if block_given?
      begin
        yield dir, optdir
      ensure
        File.unlink(file)
        Dir.rmdir(optdir) rescue nil
      end
    else
      return dir, optdir
    end
  end

  def setup_options_home(&block)
    setup_options({}, ".options", &block)
  end

  def setup_options_xdg_config_home(&block)
    setup_options({'XDG_CONFIG_HOME'=>@tmpdir+"/xdg"}, "xdg", ".options", &block)
  end

  def setup_options_home_config(&block)
    setup_options({}, ".config", ".options", &block)
  end

  def setup_options_xdg_config_dirs(&block)
    setup_options({'XDG_CONFIG_DIRS'=>@tmpdir+"/xdgconf"}, "xdgconf", ".options", &block)
  end

  def setup_options_home_config_settings(&block)
    setup_options({}, "config/settings", ".options", &block)
  end

  def test_load_home_options
    result, = setup_options_home
    assert_load(result)

    setup_options_xdg_config_home do
      assert_load(result)
    end

    setup_options_home_config do
      assert_load(result)
    end

    setup_options_xdg_config_dirs do
      assert_load(result)
    end

    setup_options_home_config_settings do
      assert_load(result)
    end
  end

  def test_load_xdg_config_home
    result, = setup_options_xdg_config_home
    assert_load(result)

    setup_options_home_config do
      assert_load(result)
    end

    setup_options_xdg_config_dirs do
      assert_load(result)
    end

    setup_options_home_config_settings do
      assert_load(result)
    end
  end

  def test_load_home_config
    result, = setup_options_home_config
    assert_load(result)

    setup_options_xdg_config_dirs do
      assert_load(result)
    end

    setup_options_home_config_settings do
      assert_load(result)
    end
  end

  def test_load_xdg_config_dirs
    result, = setup_options_xdg_config_dirs
    assert_load(result)

    setup_options_home_config_settings do
      assert_load(result)
    end
  end

  def test_load_home_config_settings
    result, = setup_options_home_config_settings
    assert_load(result)
  end

  def test_load_nothing
    setup_options({}, "") do
      assert_load_nothing
    end
  end
end
