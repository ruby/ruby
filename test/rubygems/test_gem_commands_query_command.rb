require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/commands/query_command'

class TestGemCommandsQueryCommand < RubyGemTestCase

  def setup
    super

    @foo_gem = quick_gem 'foo' do |spec|
      spec.summary = 'This is a lot of text.  ' * 5
    end
    @bar_gem = quick_gem 'bar'

    @cmd = Gem::Commands::QueryCommand.new
  end

  def test_execute
    util_setup_source_info_cache @foo_gem

    @cmd.handle_options %w[-r]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF

*** REMOTE GEMS ***

foo (0.0.2)
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_details
    util_setup_source_info_cache @foo_gem

    @cmd.handle_options %w[-r -d]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF

*** REMOTE GEMS ***

foo (0.0.2)
    This is a lot of text.  This is a lot of text.  This is a lot of
    text.  This is a lot of text.  This is a lot of text.
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_no_versions
    util_setup_source_info_cache @foo_gem, @bar_gem

    @cmd.handle_options %w[-r --no-versions]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF

*** REMOTE GEMS ***

bar
foo
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

end

