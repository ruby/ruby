require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/commands/contents_command'

class TestGemCommandsContentsCommand < RubyGemTestCase

  def setup
    super

    @cmd = Gem::Commands::ContentsCommand.new
  end

  def test_execute
    @cmd.options[:args] = %w[foo]
    quick_gem 'foo' do |gem|
      gem.files = %w[lib/foo.rb Rakefile]
    end

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r|lib/foo\.rb|, @ui.output
    assert_match %r|Rakefile|, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_all
    @cmd.options[:all] = true

    quick_gem 'foo' do |gem|
      gem.files = %w[lib/foo.rb Rakefile]
    end

    quick_gem 'bar' do |gem|
      gem.files = %w[lib/bar.rb Rakefile]
    end

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r|lib/foo\.rb|, @ui.output
    assert_match %r|lib/bar\.rb|, @ui.output
    assert_match %r|Rakefile|, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_bad_gem
    @cmd.options[:args] = %w[foo]

    assert_raises MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_match %r|Unable to find gem 'foo' in default gem paths|, @ui.output
    assert_match %r|Directories searched:|, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_exact_match
    @cmd.options[:args] = %w[foo]
    quick_gem 'foo' do |gem|
      gem.files = %w[lib/foo.rb Rakefile]
    end

    quick_gem 'foo_bar' do |gem|
      gem.files = %w[lib/foo_bar.rb Rakefile]
    end

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r|lib/foo\.rb|, @ui.output
    assert_match %r|Rakefile|, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_lib_only
    @cmd.options[:args] = %w[foo]
    @cmd.options[:lib_only] = true

    quick_gem 'foo' do |gem|
      gem.files = %w[lib/foo.rb Rakefile]
    end

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r|lib/foo\.rb|, @ui.output
    refute_match %r|Rakefile|, @ui.output

    assert_equal "", @ui.error
  end

  def test_execute_multiple
    @cmd.options[:args] = %w[foo bar]
    quick_gem 'foo' do |gem|
      gem.files = %w[lib/foo.rb Rakefile]
    end

    quick_gem 'bar' do |gem|
      gem.files = %w[lib/bar.rb Rakefile]
    end

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r|lib/foo\.rb|, @ui.output
    assert_match %r|lib/bar\.rb|, @ui.output
    assert_match %r|Rakefile|, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_no_prefix
    @cmd.options[:args] = %w[foo]
    @cmd.options[:prefix] = false

    quick_gem 'foo' do |gem|
      gem.files = %w[lib/foo.rb Rakefile]
    end

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
lib/foo.rb
Rakefile
    EOF

    assert_equal expected, @ui.output

    assert_equal "", @ui.error
  end

  def test_handle_options
    assert_equal false, @cmd.options[:lib_only]
    assert_equal [], @cmd.options[:specdirs]
    assert_equal nil, @cmd.options[:version]

    @cmd.send :handle_options, %w[-l -s foo --version 0.0.2]

    assert_equal true, @cmd.options[:lib_only]
    assert_equal %w[foo], @cmd.options[:specdirs]
    assert_equal Gem::Requirement.new('0.0.2'), @cmd.options[:version]
  end

end

