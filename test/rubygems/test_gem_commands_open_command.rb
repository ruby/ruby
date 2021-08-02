# frozen_string_literal: true
require_relative 'helper'
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

    gem 'foo', '1.0.0'
    spec = gem 'foo', '1.0.1'

    assert_nothing_raised Gem::MockGemUi::TermError do
      Dir.stub(:chdir, spec.full_gem_path) do
        use_ui @ui do
          @cmd.execute
        end
      end
    end

    assert_equal "", @ui.error
  end

  def test_wrong_version
    @cmd.options[:version] = "4.0"
    @cmd.options[:args] = %w[foo]

    gem "foo", "5.0"

    assert_raise Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_match %r{Unable to find gem 'foo'}, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_bad_gem
    @cmd.options[:args] = %w[foo]

    assert_raise Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_match %r{Unable to find gem 'foo'}, @ui.output
    assert_equal "", @ui.error
  end

  def test_default_gem
    @cmd.options[:version] = "1.0"
    @cmd.options[:args] = %w[foo]

    version = @cmd.options[:version]
    @cmd.define_singleton_method(:spec_for) do |name|
      spec = Gem::Specification.find_all_by_name(name, version).first

      spec.define_singleton_method(:default_gem?) do
        true
      end

      return spec if spec

      say "Unable to find gem '#{name}'"
    end

    gem("foo", "1.0")

    assert_raise Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_match %r{'foo' is a default gem and can't be opened\.} , @ui.output
    assert_equal "", @ui.error
  end
end
