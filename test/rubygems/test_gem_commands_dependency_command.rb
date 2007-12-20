require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/commands/dependency_command'

class TestGemCommandsDependencyCommand < RubyGemTestCase

  def setup
    super

    @cmd = Gem::Commands::DependencyCommand.new
    @cmd.options[:domain] = :local
  end

  def test_execute
    quick_gem 'foo' do |gem|
      gem.add_dependency 'bar', '> 1'
    end

    @cmd.options[:args] = %w[foo]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "Gem foo-2\n  bar (> 1)\n\n", @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_no_match
    @cmd.options[:args] = %w[foo]

    assert_raise MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal "No match found for foo (>= 0)\n", @ui.output
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

  def test_execute_reverse
    quick_gem 'foo' do |gem|
      gem.add_dependency 'bar', '> 1'
    end

    quick_gem 'baz' do |gem|
      gem.add_dependency 'foo'
    end

    @cmd.options[:args] = %w[foo]
    @cmd.options[:reverse_dependencies] = true

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
Gem foo-2
  bar (> 1)
  Used by
    baz-2 (foo (>= 0))

    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_remote
    foo = quick_gem 'foo' do |gem|
      gem.add_dependency 'bar', '> 1'
    end

    util_setup_source_info_cache foo

    FileUtils.rm File.join(@gemhome, 'specifications',
                           "#{foo.full_name}.gemspec")

    @cmd.options[:args] = %w[foo]
    @cmd.options[:domain] = :remote

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "Gem foo-2\n  bar (> 1)\n\n", @ui.output
    assert_equal '', @ui.error
  end

end

