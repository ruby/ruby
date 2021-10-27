# frozen_string_literal: true
require_relative 'helper'
require 'rubygems/commands/dependency_command'

class TestGemCommandsDependencyCommand < Gem::TestCase
  def setup
    super
    @stub_ui = Gem::MockGemUi.new
    @cmd = Gem::Commands::DependencyCommand.new
    @cmd.options[:domain] = :local
  end

  def test_execute
    quick_gem 'foo' do |gem|
      gem.add_dependency 'bar', '> 1'
      gem.add_dependency 'baz', '> 1'
    end

    @cmd.options[:args] = %w[foo]

    use_ui @stub_ui do
      @cmd.execute
    end

    assert_equal "Gem foo-2\n  bar (> 1)\n  baz (> 1)\n\n",
                 @stub_ui.output
    assert_equal '', @stub_ui.error
  end

  def test_execute_no_args
    install_specs util_spec 'x', '2'

    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.spec 'a', '2.a'
      fetcher.spec 'dep_x', 1, 'x' => '>= 1'
      fetcher.legacy_platform
    end

    @cmd.options[:args] = []

    use_ui @stub_ui do
      @cmd.execute
    end

    expected = <<-EOF
Gem a-1

Gem a-2.a

Gem dep_x-1
  x (>= 1)

Gem pl-1-x86-linux

Gem x-2

    EOF

    assert_equal expected, @stub_ui.output
    assert_equal '', @stub_ui.error
  end

  def test_execute_no_match
    @cmd.options[:args] = %w[foo]

    assert_raise Gem::MockGemUi::TermError do
      use_ui @stub_ui do
        @cmd.execute
      end
    end

    assert_equal "No gems found matching foo (>= 0)\n", @stub_ui.output
    assert_equal '', @stub_ui.error
  end

  def test_execute_pipe_format
    spec = util_spec 'foo' do |gem|
      gem.add_dependency 'bar', '> 1'
    end
    install_specs util_spec 'bar', 2
    install_specs spec

    @cmd.options[:args] = %w[foo]
    @cmd.options[:pipe_format] = true

    use_ui @stub_ui do
      @cmd.execute
    end

    assert_equal "bar --version '> 1'\n", @stub_ui.output
    assert_equal '', @stub_ui.error
  end

  def test_execute_regexp
    spec_fetcher do |fetcher|
      fetcher.spec 'a',      1
      fetcher.spec 'a',      '2.a'
      fetcher.spec 'a_evil', 9
      fetcher.spec 'b',      2
    end

    @cmd.options[:args] = %w[[ab]]

    use_ui @stub_ui do
      @cmd.execute
    end

    expected = <<-EOF
Gem a-1

Gem a-2.a

Gem a_evil-9

Gem b-2

    EOF

    assert_equal expected, @stub_ui.output
    assert_equal '', @stub_ui.error
  end

  def test_execute_reverse
    # FIX: this shouldn't need to write out, but fails if you switch it
    quick_gem 'foo' do |gem|
      gem.add_dependency 'bar', '> 1'
    end

    quick_gem 'baz' do |gem|
      gem.add_dependency 'foo'
    end

    @cmd.options[:args] = %w[foo]
    @cmd.options[:reverse_dependencies] = true

    use_ui @stub_ui do
      @cmd.execute
    end

    expected = <<-EOF
Gem foo-2
  bar (> 1)
  Used by
    baz-2 (foo (>= 0))

    EOF

    assert_equal expected, @stub_ui.output
    assert_equal '', @stub_ui.error
  end

  def test_execute_reverse_remote
    @cmd.options[:args] = %w[foo]
    @cmd.options[:reverse_dependencies] = true
    @cmd.options[:domain] = :remote

    assert_raise Gem::MockGemUi::TermError do
      use_ui @stub_ui do
        @cmd.execute
      end
    end

    expected = <<-EOF
ERROR:  Only reverse dependencies for local gems are supported.
    EOF

    assert_equal '', @stub_ui.output
    assert_equal expected, @stub_ui.error
  end

  def test_execute_remote
    install_specs util_spec 'bar', '2'

    spec_fetcher do |fetcher|
      fetcher.spec 'foo', 2, 'bar' => '> 1'
    end

    @cmd.options[:args] = %w[foo]
    @cmd.options[:domain] = :remote

    use_ui @stub_ui do
      @cmd.execute
    end

    assert_equal "Gem foo-2\n  bar (> 1)\n\n", @stub_ui.output
    assert_equal '', @stub_ui.error
  end

  def test_execute_remote_version
    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher

    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.spec 'a', 2
    end

    @cmd.options[:args] = %w[a]
    @cmd.options[:domain] = :remote
    @cmd.options[:version] = req '= 1'

    use_ui @stub_ui do
      @cmd.execute
    end

    assert_equal "Gem a-1\n\n", @stub_ui.output
    assert_equal '', @stub_ui.error
  end

  def test_execute_prerelease
    spec_fetcher do |fetcher|
      fetcher.spec 'a', '2.a'
    end

    @cmd.options[:args] = %w[a]
    @cmd.options[:domain] = :remote
    @cmd.options[:prerelease] = true

    use_ui @stub_ui do
      @cmd.execute
    end

    assert_equal "Gem a-2.a\n\n", @stub_ui.output
    assert_equal '', @stub_ui.error
  end
end
