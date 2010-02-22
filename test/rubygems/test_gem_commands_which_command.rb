require_relative 'gemutilities'
require 'rubygems/commands/which_command'

class TestGemCommandsWhichCommand < RubyGemTestCase

  def setup
    super
    @cmd = Gem::Commands::WhichCommand.new
  end

  def test_execute
    util_foo_bar

    @cmd.handle_options %w[foo_bar]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "#{@foo_bar.full_gem_path}/lib/foo_bar.rb\n", @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_one_missing
    util_foo_bar

    @cmd.handle_options %w[foo_bar missing]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "#{@foo_bar.full_gem_path}/lib/foo_bar.rb\n", @ui.output
    assert_match %r%Can't find ruby library file or shared library missing\n%,
                 @ui.error
  end

  def test_execute_missing
    @cmd.handle_options %w[missing]

    use_ui @ui do
      assert_raises MockGemUi::TermError do
        @cmd.execute
      end
    end

    assert_equal '', @ui.output
    assert_match %r%Can't find ruby library file or shared library missing\n%,
                 @ui.error
  end

  def util_foo_bar
    files = %w[lib/foo_bar.rb Rakefile]
    @foo_bar = quick_gem 'foo_bar' do |gem|
      gem.files = files
    end

    files.each do |file|
      filename = @foo_bar.full_gem_path + "/#{file}"
      FileUtils.mkdir_p File.dirname(filename)
      FileUtils.touch filename
    end
  end

end

