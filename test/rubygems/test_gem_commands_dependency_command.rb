require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/commands/dependency_command'

class TestGemCommandsDependencyCommand < RubyGemTestCase

  def setup
    super

    @cmd = Gem::Commands::DependencyCommand.new
    @cmd.options[:domain] = :local

    util_setup_fake_fetcher
  end

  def test_execute
    quick_gem 'foo' do |gem|
      gem.add_dependency 'bar', '> 1'
    end

    Gem.source_index = nil

    @cmd.options[:args] = %w[foo]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "Gem foo-2\n  bar (> 1, runtime)\n\n", @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_no_args
    Gem.source_index = nil

    @cmd.options[:args] = []

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
Gem a-1

Gem a-2

Gem a_evil-9

Gem b-2

Gem c-1.2

Gem pl-1-x86-linux

    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_no_match
    @cmd.options[:args] = %w[foo]

    assert_raises MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal "No gems found matching foo (>= 0)\n", @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_pipe_format
    quick_gem 'foo' do |gem|
      gem.add_dependency 'bar', '> 1'
    end

    @cmd.options[:args] = %w[foo]
    @cmd.options[:pipe_format] = true

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "bar --version '> 1'\n", @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_regexp
    Gem.source_index = nil

    @cmd.options[:args] = %w[/[ab]/]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
Gem a-1

Gem a-2

Gem a_evil-9

Gem b-2

    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_reverse
    quick_gem 'foo' do |gem|
      gem.add_dependency 'bar', '> 1'
    end

    quick_gem 'baz' do |gem|
      gem.add_dependency 'foo'
    end

    Gem.source_index = nil

    @cmd.options[:args] = %w[foo]
    @cmd.options[:reverse_dependencies] = true

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
Gem foo-2
  bar (> 1, runtime)
  Used by
    baz-2 (foo (>= 0, runtime))

    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_reverse_remote
    @cmd.options[:args] = %w[foo]
    @cmd.options[:reverse_dependencies] = true
    @cmd.options[:domain] = :remote

    assert_raises MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    expected = <<-EOF
ERROR:  Only reverse dependencies for local gems are supported.
    EOF

    assert_equal '', @ui.output
    assert_equal expected, @ui.error
  end

  def test_execute_remote
    foo = quick_gem 'foo' do |gem|
      gem.add_dependency 'bar', '> 1'
    end

    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher

    util_setup_spec_fetcher foo

    FileUtils.rm File.join(@gemhome, 'specifications',
                           "#{foo.full_name}.gemspec")

    @cmd.options[:args] = %w[foo]
    @cmd.options[:domain] = :remote

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "Gem foo-2\n  bar (> 1, runtime)\n\n", @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_remote_legacy
    foo = quick_gem 'foo' do |gem|
      gem.add_dependency 'bar', '> 1'
    end

    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher

    Gem::SpecFetcher.fetcher = nil
    si = util_setup_source_info_cache foo

    @fetcher.data["#{@gem_repo}yaml"] = YAML.dump si
    @fetcher.data["#{@gem_repo}Marshal.#{Gem.marshal_version}"] =
      si.dump

    @fetcher.data.delete "#{@gem_repo}latest_specs.#{Gem.marshal_version}.gz"

    FileUtils.rm File.join(@gemhome, 'specifications',
                           "#{foo.full_name}.gemspec")

    @cmd.options[:args] = %w[foo]
    @cmd.options[:domain] = :remote

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "Gem foo-2\n  bar (> 1, runtime)\n\n", @ui.output

    expected = <<-EOF
WARNING:  RubyGems 1.2+ index not found for:
\t#{@gem_repo}

RubyGems will revert to legacy indexes degrading performance.
    EOF

    assert_equal expected, @ui.error
  end

end

