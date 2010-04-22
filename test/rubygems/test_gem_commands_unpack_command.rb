require_relative 'gemutilities'
require 'rubygems/commands/unpack_command'

class TestGemCommandsUnpackCommand < RubyGemTestCase

  def setup
    super

    Dir.chdir @tempdir do
      @cmd = Gem::Commands::UnpackCommand.new
    end
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
    util_make_gems

    Gem.clear_paths

    gemhome2 = File.join @tempdir, 'gemhome2'

    Gem.send :set_paths, [gemhome2, @gemhome].join(File::PATH_SEPARATOR)
    Gem.send :set_home, gemhome2

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    assert File.exist?(File.join(@tempdir, 'a-3.a'))
  end

  def test_execute_gem_path_missing
    util_make_gems
    util_setup_spec_fetcher

    Gem.clear_paths

    gemhome2 = File.join @tempdir, 'gemhome2'

    Gem.send :set_paths, [gemhome2, @gemhome].join(File::PATH_SEPARATOR)
    Gem.send :set_home, gemhome2

    @cmd.options[:args] = %w[z]

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    assert_equal '', @ui.output
  end

  def test_execute_remote
    util_setup_fake_fetcher
    util_setup_spec_fetcher @a1, @a2
    util_clear_gems

    a2_data = nil
    open File.join(@gemhome, 'cache', @a2.file_name), 'rb' do |fp|
      a2_data = fp.read
    end

    Gem::RemoteFetcher.fetcher.data['http://gems.example.com/gems/a-2.gem'] =
      a2_data

    Gem.configuration.verbose = :really
    @cmd.options[:args] = %w[a]

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    assert File.exist?(File.join(@tempdir, 'a-2')), 'a should be unpacked'
  end

  def test_execute_sudo
    util_make_gems

    File.chmod 0555, @gemhome

    @cmd.options[:args] = %w[b]

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    assert File.exist?(File.join(@tempdir, 'b-2')), 'b should be unpacked'
  ensure
    File.chmod 0755, @gemhome
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
    foo_spec = quick_gem 'foo'
    foo_bar_spec = quick_gem 'foo_bar'

    use_ui @ui do
      Dir.chdir @tempdir do
        Gem::Builder.new(foo_spec).build
        Gem::Builder.new(foo_bar_spec).build
      end
    end

    foo_path = File.join(@tempdir, "#{foo_spec.full_name}.gem")
    foo_bar_path = File.join(@tempdir, "#{foo_bar_spec.full_name}.gem")
    Gem::Installer.new(foo_path).install
    Gem::Installer.new(foo_bar_path).install

    @cmd.options[:args] = %w[foo]

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    assert File.exist?(File.join(@tempdir, foo_spec.full_name))
  end

end

