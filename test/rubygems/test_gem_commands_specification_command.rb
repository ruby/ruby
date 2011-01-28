######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require 'rubygems/test_case'
require 'rubygems/commands/specification_command'

class TestGemCommandsSpecificationCommand < Gem::TestCase

  def setup
    super

    @cmd = Gem::Commands::SpecificationCommand.new
  end

  def test_execute
    foo = quick_gem 'foo'
    Gem.source_index.add_spec foo

    @cmd.options[:args] = %w[foo]

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r|Gem::Specification|, @ui.output
    assert_match %r|name: foo|, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_all
    quick_gem 'foo', '0.0.1'
    quick_gem 'foo', '0.0.2'

    @cmd.options[:args] = %w[foo]
    @cmd.options[:all] = true

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r|Gem::Specification|, @ui.output
    assert_match %r|name: foo|, @ui.output
    assert_match %r|version: 0.0.1|, @ui.output
    assert_match %r|version: 0.0.2|, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_bad_name
    @cmd.options[:args] = %w[foo]

    assert_raises Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal '', @ui.output
    assert_equal "ERROR:  Unknown gem 'foo'\n", @ui.error
  end

  def test_execute_exact_match
    quick_gem 'foo'
    quick_gem 'foo_bar'

    @cmd.options[:args] = %w[foo]

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r|Gem::Specification|, @ui.output
    assert_match %r|name: foo|, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_field
    foo = quick_gem 'foo'
    Gem.source_index.add_spec foo

    @cmd.options[:args] = %w[foo name]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "foo", YAML.load(@ui.output)
  end

  def test_execute_marshal
    foo = quick_gem 'foo'
    Gem.source_index.add_spec foo

    @cmd.options[:args] = %w[foo]
    @cmd.options[:format] = :marshal

    use_ui @ui do
      @cmd.execute
    end

    assert_equal foo, Marshal.load(@ui.output)
    assert_equal '', @ui.error
  end

  def test_execute_remote
    foo = quick_gem 'foo'

    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher

    util_setup_spec_fetcher foo

    FileUtils.rm File.join(@gemhome, 'specifications', foo.spec_name)

    @cmd.options[:args] = %w[foo]
    @cmd.options[:domain] = :remote

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r|\A--- !ruby/object:Gem::Specification|, @ui.output
    assert_match %r|name: foo|, @ui.output
  end

  def test_execute_ruby
    foo = quick_gem 'foo'
    Gem.source_index.add_spec foo

    @cmd.options[:args] = %w[foo]
    @cmd.options[:format] = :ruby

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r|Gem::Specification.new|, @ui.output
    assert_match %r|s.name = %q\{foo\}|, @ui.output
    assert_equal '', @ui.error
  end

end

