# frozen_string_literal: true
require_relative 'helper'
require 'rubygems/commands/unpack_command'

class TestGemCommandsUnpackCommand < Gem::TestCase
  def setup
    super

    Dir.chdir @tempdir do
      @cmd = Gem::Commands::UnpackCommand.new
    end
  end

  def test_find_in_cache
    util_make_gems

    assert_equal(
      @cmd.find_in_cache(File.basename @a1.cache_file),
      @a1.cache_file,
      'found a-1.gem in the cache'
    )
  end

  def test_get_path
    specs = spec_fetcher do |fetcher|
      fetcher.gem 'a', 1
    end

    dep = Gem::Dependency.new 'a', 1
    assert_equal(
      @cmd.get_path(dep),
      specs['a-1'].cache_file,
      'fetches a-1 and returns the cache path'
    )

    FileUtils.rm specs['a-1'].cache_file

    assert_equal(
      @cmd.get_path(dep),
      specs['a-1'].cache_file,
      'when removed from cache, refetches a-1'
    )
  end

  def test_execute
    util_make_gems

    @cmd.options[:args] = %w[a b]

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    assert File.exist?(File.join(@tempdir, 'a-3.a')), 'a should be unpacked'
    assert File.exist?(File.join(@tempdir, 'b-2')),   'b should be unpacked'
  end

  def test_execute_gem_path
    spec_fetcher do |fetcher|
      fetcher.gem 'a', '3.a'
    end

    Gem.clear_paths

    gemhome2 = File.join @tempdir, 'gemhome2'

    Gem.use_paths gemhome2, [gemhome2, @gemhome]

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    assert File.exist?(File.join(@tempdir, 'a-3.a'))
  end

  def test_execute_gem_path_missing
    spec_fetcher

    Gem.clear_paths

    gemhome2 = File.join @tempdir, 'gemhome2'

    Gem.use_paths gemhome2, [gemhome2, @gemhome]

    @cmd.options[:args] = %w[z]

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    assert_equal '', @ui.output
  end

  def test_execute_remote
    spec_fetcher do |fetcher|
      fetcher.download 'a', 1
      fetcher.download 'a', 2
    end

    Gem.configuration.verbose = :really
    @cmd.options[:args] = %w[a]

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    assert File.exist?(File.join(@tempdir, 'a-2')), 'a should be unpacked'
  end

  def test_execute_spec
    util_make_gems

    @cmd.options[:args] = %w[a b]
    @cmd.options[:spec] = true

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    assert File.exist?(File.join(@tempdir, 'a-3.a.gemspec'))
    assert File.exist?(File.join(@tempdir, 'b-2.gemspec'))
  end

  def test_execute_spec_target
    util_make_gems

    @cmd.options[:args] = %w[a b]
    @cmd.options[:target] = 'specs'
    @cmd.options[:spec] = true

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    assert File.exist?(File.join(@tempdir, 'specs/a-3.a.gemspec'))
    assert File.exist?(File.join(@tempdir, 'specs/b-2.gemspec'))
  end

  def test_execute_sudo
    pend 'Cannot perform this test on windows (chmod)' if win_platform?

    util_make_gems

    FileUtils.chmod 0555, @gemhome

    @cmd.options[:args] = %w[b]

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    assert File.exist?(File.join(@tempdir, 'b-2')), 'b should be unpacked'
  ensure
    FileUtils.chmod 0755, @gemhome
  end

  def test_execute_with_target_option
    util_make_gems

    target = 'with_target'
    @cmd.options[:args] = %w[a]
    @cmd.options[:target] = target

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    assert File.exist?(File.join(@tempdir, target, 'a-3.a'))
  end

  def test_execute_exact_match
    foo_spec = util_spec 'foo'
    foo_bar_spec = util_spec 'foo_bar'

    use_ui @ui do
      Dir.chdir @tempdir do
        Gem::Package.build foo_spec
        Gem::Package.build foo_bar_spec
      end
    end

    foo_path = File.join(@tempdir, "#{foo_spec.full_name}.gem")
    foo_bar_path = File.join(@tempdir, "#{foo_bar_spec.full_name}.gem")
    Gem::Installer.at(foo_path).install
    Gem::Installer.at(foo_bar_path).install

    @cmd.options[:args] = %w[foo]

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    assert_path_exist File.join(@tempdir, foo_spec.full_name)
  end

  def test_handle_options_metadata
    refute @cmd.options[:spec]

    @cmd.send :handle_options, %w[--spec a]

    assert @cmd.options[:spec]
  end
end
