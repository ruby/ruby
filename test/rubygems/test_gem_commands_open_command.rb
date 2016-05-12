# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/commands/open_command'

class TestGemCommandsOpenCommand < Gem::TestCase

  def setup
    super

    @cmd = Gem::Commands::OpenCommand.new
  end

  def gem(name, version = "1.0")
    spec = quick_gem name do |gem|
      gem.files = %W[lib/#{name}.rb Rakefile]
      gem.version = version
    end
    write_file File.join(*%W[gems #{spec.full_name} lib #{name}.rb])
    write_file File.join(*%W[gems #{spec.full_name} Rakefile])
    spec
  end

  def test_execute
    @cmd.options[:args] = %w[foo]
    @cmd.options[:editor] = "#{Gem.ruby} -e0 --"

    spec = gem 'foo'
    mock = MiniTest::Mock.new
    mock.expect(:call, true, [spec.full_gem_path])

    Dir.stub(:chdir, mock) do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert mock.verify
    assert_equal "", @ui.error
  end

  def test_wrong_version
    @cmd.options[:version] = "4.0"
    @cmd.options[:args] = %w[foo]

    gem "foo", "5.0"

    assert_raises Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_match %r|Unable to find gem 'foo'|, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_bad_gem
    @cmd.options[:args] = %w[foo]

    assert_raises Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_match %r|Unable to find gem 'foo'|, @ui.output
    assert_equal "", @ui.error
  end

end
