# frozen_string_literal: true
require_relative "helper"
require "rubygems/commands/specification_command"

class TestGemCommandsSpecificationCommand < Gem::TestCase
  def setup
    super

    @cmd = Gem::Commands::SpecificationCommand.new
  end

  def test_execute
    foo = util_spec "foo"

    install_specs foo

    @cmd.options[:args] = %w[foo]

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r{Gem::Specification}, @ui.output
    assert_match %r{name: foo}, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_all
    install_specs util_spec "foo", "0.0.1"
    install_specs util_spec "foo", "0.0.2"

    @cmd.options[:args] = %w[foo]
    @cmd.options[:all] = true

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r{Gem::Specification}, @ui.output
    assert_match %r{name: foo}, @ui.output
    assert_match %r{version: 0.0.1}, @ui.output
    assert_match %r{version: 0.0.2}, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_all_conflicts_with_version
    util_spec "foo", "0.0.1"
    util_spec "foo", "0.0.2"

    @cmd.options[:args] = %w[foo]
    @cmd.options[:all] = true
    @cmd.options[:version] = "1"

    assert_raise Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal "", @ui.output
    assert_equal "ERROR:  Specify --all or -v, not both\n", @ui.error
  end

  def test_execute_bad_name
    @cmd.options[:args] = %w[foo]

    assert_raise Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal "", @ui.output
    assert_equal "ERROR:  No gem matching 'foo (>= 0)' found\n", @ui.error
  end

  def test_execute_bad_name_with_version
    @cmd.options[:args] = %w[foo]
    @cmd.options[:version] = "1.3.2"

    assert_raise Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal "", @ui.output
    assert_equal "ERROR:  No gem matching 'foo (= 1.3.2)' found\n", @ui.error
  end

  def test_execute_exact_match
    install_specs util_spec "foo"
    install_specs util_spec "foo_bar"

    @cmd.options[:args] = %w[foo]

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r{Gem::Specification}, @ui.output
    assert_match %r{name: foo}, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_field
    foo = util_spec "foo", "2"

    install_specs foo

    @cmd.options[:args] = %w[foo name]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "foo", load_yaml(@ui.output)
  end

  def test_execute_file
    foo = util_spec "foo" do |s|
      s.files = %w[lib/code.rb]
    end

    util_build_gem foo

    @cmd.options[:args] = [foo.cache_file]

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r{Gem::Specification}, @ui.output
    assert_match %r{name: foo}, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_marshal
    foo = util_spec "foo", "2"

    install_specs foo

    @cmd.options[:args] = %w[foo]
    @cmd.options[:format] = :marshal

    use_ui @ui do
      @cmd.execute
    end

    assert_equal foo, Marshal.load(@ui.output)
    assert_equal "", @ui.error
  end

  def test_execute_remote
    spec_fetcher do |fetcher|
      fetcher.spec "foo", 1
    end

    @cmd.options[:args] = %w[foo]
    @cmd.options[:domain] = :remote

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r{\A--- !ruby/object:Gem::Specification}, @ui.output
    assert_match %r{name: foo}, @ui.output
  end

  def test_execute_remote_with_version
    spec_fetcher do |fetcher|
      fetcher.spec "foo", "1"
      fetcher.spec "foo", "2"
    end

    @cmd.options[:args] = %w[foo]
    @cmd.options[:version] = "1"
    @cmd.options[:domain] = :remote

    use_ui @ui do
      @cmd.execute
    end

    spec = Gem::Specification.from_yaml @ui.output

    assert_equal Gem::Version.new("1"), spec.version
  end

  def test_execute_remote_with_version_and_platform
    original_platforms = Gem.platforms.dup

    spec_fetcher do |fetcher|
      fetcher.spec "foo", "1"
      fetcher.spec "foo", "1" do |s|
        s.platform = "x86_64-linux"
      end
    end

    @cmd.options[:args] = %w[foo]
    @cmd.options[:version] = "1"
    @cmd.options[:domain] = :remote
    @cmd.options[:added_platform] = true
    Gem.platforms = [Gem::Platform::RUBY, Gem::Platform.new("x86_64-linux")]

    use_ui @ui do
      @cmd.execute
    end

    spec = Gem::Specification.from_yaml @ui.output

    assert_equal Gem::Version.new("1"), spec.version
    assert_equal Gem::Platform.new("x86_64-linux"), spec.platform
  ensure
    Gem.platforms = original_platforms
  end

  def test_execute_remote_without_prerelease
    spec_fetcher do |fetcher|
      fetcher.spec "foo", "2.0.0"
      fetcher.spec "foo", "2.0.1.pre"
    end

    @cmd.options[:args] = %w[foo]
    @cmd.options[:domain] = :remote

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r{\A--- !ruby/object:Gem::Specification}, @ui.output
    assert_match %r{name: foo}, @ui.output

    spec = load_yaml @ui.output

    assert_equal Gem::Version.new("2.0.0"), spec.version
  end

  def test_execute_remote_with_prerelease
    spec_fetcher do |fetcher|
      fetcher.spec "foo", "2.0.0"
      fetcher.spec "foo", "2.0.1.pre"
    end

    @cmd.options[:args] = %w[foo]
    @cmd.options[:domain] = :remote
    @cmd.options[:prerelease] = true

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r{\A--- !ruby/object:Gem::Specification}, @ui.output
    assert_match %r{name: foo}, @ui.output

    spec = load_yaml @ui.output

    assert_equal Gem::Version.new("2.0.1.pre"), spec.version
  end

  def test_execute_ruby
    foo = util_spec "foo"

    install_specs foo

    @cmd.options[:args] = %w[foo]
    @cmd.options[:format] = :ruby

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r{Gem::Specification.new}, @ui.output
    assert_match %r{s.name = "foo"}, @ui.output
    assert_equal "", @ui.error
  end
end
