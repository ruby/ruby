require 'rubygems/test_case'
require 'rubygems/commands/specification_command'

class TestGemCommandsSpecificationCommand < Gem::TestCase

  def setup
    super

    @cmd = Gem::Commands::SpecificationCommand.new
  end

  def test_execute
    foo = quick_spec 'foo'

    install_specs foo

    @cmd.options[:args] = %w[foo]

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r|Gem::Specification|, @ui.output
    assert_match %r|name: foo|, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_all
    quick_spec 'foo', '0.0.1'
    quick_spec 'foo', '0.0.2'

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

  def test_execute_all_conflicts_with_version
    quick_spec 'foo', '0.0.1'
    quick_spec 'foo', '0.0.2'

    @cmd.options[:args] = %w[foo]
    @cmd.options[:all] = true
    @cmd.options[:version] = "1"

    assert_raises Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal '', @ui.output
    assert_equal "ERROR:  Specify --all or -v, not both\n", @ui.error
  end

  def test_execute_bad_name
    @cmd.options[:args] = %w[foo]

    assert_raises Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal '', @ui.output
    assert_equal "ERROR:  No gem matching 'foo (>= 0)' found\n", @ui.error
  end

  def test_execute_bad_name_with_version
    @cmd.options[:args] = %w[foo]
    @cmd.options[:version] = "1.3.2"

    assert_raises Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal '', @ui.output
    assert_equal "ERROR:  No gem matching 'foo (= 1.3.2)' found\n", @ui.error
  end

  def test_execute_exact_match
    quick_spec 'foo'
    quick_spec 'foo_bar'

    @cmd.options[:args] = %w[foo]

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r|Gem::Specification|, @ui.output
    assert_match %r|name: foo|, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_field
    foo = new_spec 'foo', '2'

    install_specs foo

    @cmd.options[:args] = %w[foo name]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "foo", YAML.load(@ui.output)
  end

  def test_execute_file
    foo = quick_spec 'foo' do |s|
      s.files = %w[lib/code.rb]
    end

    util_build_gem foo

    @cmd.options[:args] = [foo.cache_file]

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r|Gem::Specification|, @ui.output
    assert_match %r|name: foo|, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_marshal
    foo = new_spec 'foo', '2'

    install_specs foo

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

  def test_execute_remote_with_version
    foo1 = quick_gem 'foo', "1"
    foo2 = quick_gem 'foo', "2"

    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher

    util_setup_spec_fetcher foo1, foo2

    FileUtils.rm File.join(@gemhome, 'specifications', foo1.spec_name)
    FileUtils.rm File.join(@gemhome, 'specifications', foo2.spec_name)

    @cmd.options[:args] = %w[foo]
    @cmd.options[:version] = "1"
    @cmd.options[:domain] = :remote

    use_ui @ui do
      @cmd.execute
    end

    spec = Gem::Specification.from_yaml @ui.output

    assert_equal Gem::Version.new("1"), spec.version
  end

  def test_execute_remote_without_prerelease
    foo = new_spec 'foo', '2.0.0'
    foo_pre = new_spec 'foo', '2.0.1.pre'

    install_specs foo, foo_pre

    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher

    util_setup_spec_fetcher foo
    util_setup_spec_fetcher foo_pre

    @cmd.options[:args] = %w[foo]
    @cmd.options[:domain] = :remote

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r|\A--- !ruby/object:Gem::Specification|, @ui.output
    assert_match %r|name: foo|, @ui.output

    spec = YAML.load @ui.output

    assert_equal Gem::Version.new("2.0.0"), spec.version
  end

  def test_execute_remote_with_prerelease
    foo = new_spec 'foo', '2.0.0'
    foo_pre = new_spec 'foo', '2.0.1.pre'

    install_specs foo, foo_pre

    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher

    util_setup_spec_fetcher foo
    util_setup_spec_fetcher foo_pre

    @cmd.options[:args] = %w[foo]
    @cmd.options[:domain] = :remote
    @cmd.options[:prerelease] = true

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r|\A--- !ruby/object:Gem::Specification|, @ui.output
    assert_match %r|name: foo|, @ui.output

    spec = YAML.load @ui.output

    assert_equal Gem::Version.new("2.0.1.pre"), spec.version
  end

  def test_execute_ruby
    foo = quick_spec 'foo'

    install_specs foo

    @cmd.options[:args] = %w[foo]
    @cmd.options[:format] = :ruby

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r|Gem::Specification.new|, @ui.output
    assert_match %r|s.name = "foo"|, @ui.output
    assert_equal '', @ui.error
  end

end

