# frozen_string_literal: true
require_relative 'helper'
require 'rubygems/commands/contents_command'

class TestGemCommandsContentsCommand < Gem::TestCase
  def setup
    super

    @cmd = Gem::Commands::ContentsCommand.new
  end

  def gem(name, version = 2)
    spec = quick_gem name, version do |gem|
      gem.files = %W[lib/#{name}.rb Rakefile]
    end
    write_file File.join(*%W[gems #{spec.full_name} lib #{name}.rb])
    write_file File.join(*%W[gems #{spec.full_name} Rakefile])
  end

  def test_execute
    @cmd.options[:args] = %w[foo]

    gem 'foo'

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r{lib/foo\.rb}, @ui.output
    assert_match %r{Rakefile}, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_all
    @cmd.options[:all] = true

    gem 'foo'
    gem 'bar'

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r{lib/foo\.rb}, @ui.output
    assert_match %r{lib/bar\.rb}, @ui.output
    assert_match %r{Rakefile}, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_bad_gem
    @cmd.options[:args] = %w[foo]

    assert_raise Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_match %r{Unable to find gem 'foo' in default gem paths}, @ui.output
    assert_match %r{Directories searched:}, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_exact_match
    @cmd.options[:args] = %w[foo]
    gem 'foo'
    gem 'bar'

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r{lib/foo\.rb}, @ui.output
    assert_match %r{Rakefile}, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_lib_only
    @cmd.options[:args] = %w[foo]
    @cmd.options[:lib_only] = true

    gem 'foo'

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r{lib/foo\.rb}, @ui.output
    refute_match %r{Rakefile}, @ui.output

    assert_equal "", @ui.error
  end

  def test_execute_missing_single
    @cmd.options[:args] = %w[foo]

    assert_raise Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_match "Unable to find gem 'foo'", @ui.output
    assert_empty @ui.error
  end

  def test_execute_missing_version
    @cmd.options[:args] = %w[foo]
    @cmd.options[:version] = Gem::Requirement.new '= 2'

    gem 'foo', 1

    assert_raise Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_match "Unable to find gem 'foo'", @ui.output
    assert_empty @ui.error
  end

  def test_execute_missing_multiple
    @cmd.options[:args] = %w[foo bar]

    gem 'foo'

    use_ui @ui do
      @cmd.execute
    end

    assert_match "lib/foo.rb",               @ui.output
    assert_match "Unable to find gem 'bar'", @ui.output

    assert_empty @ui.error
  end

  def test_execute_multiple
    @cmd.options[:args] = %w[foo bar]

    gem 'foo'
    gem 'bar'

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r{lib/foo\.rb}, @ui.output
    assert_match %r{lib/bar\.rb}, @ui.output
    assert_match %r{Rakefile}, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_show_install_dir
    @cmd.options[:args] = %w[foo]
    @cmd.options[:show_install_dir] = true

    gem 'foo'

    use_ui @ui do
      @cmd.execute
    end

    expected = File.join @gemhome, 'gems', 'foo-2'

    assert_equal "#{expected}\n", @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_show_install_dir_latest_version
    @cmd.options[:args] = %w[foo]
    @cmd.options[:show_install_dir] = true

    gem 'foo', 1
    gem 'foo', 2

    use_ui @ui do
      @cmd.execute
    end

    expected = File.join @gemhome, 'gems', 'foo-2'

    assert_equal "#{expected}\n", @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_show_install_dir_version
    @cmd.options[:args] = %w[foo]
    @cmd.options[:show_install_dir] = true
    @cmd.options[:version] = Gem::Requirement.new '= 1'

    gem 'foo', 1
    gem 'foo', 2

    use_ui @ui do
      @cmd.execute
    end

    expected = File.join @gemhome, 'gems', 'foo-1'

    assert_equal "#{expected}\n", @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_no_prefix
    @cmd.options[:args] = %w[foo]
    @cmd.options[:prefix] = false

    gem 'foo'

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
Rakefile
lib/foo.rb
    EOF

    assert_equal expected, @ui.output

    assert_equal "", @ui.error
  end

  def test_execute_default_gem
    default_gem_spec = new_default_spec("default", "2.0.0.0",
                                        nil, "default/gem.rb")
    default_gem_spec.executables = ["default_command"]
    default_gem_spec.files += ["default_gem.so"]
    install_default_gems(default_gem_spec)

    @cmd.options[:args] = %w[default]

    use_ui @ui do
      @cmd.execute
    end

    expected = [
      [RbConfig::CONFIG['bindir'], 'default_command'],
      [RbConfig::CONFIG['rubylibdir'], 'default/gem.rb'],
      [RbConfig::CONFIG['archdir'], 'default_gem.so'],
    ].sort.map{|a|File.join a }.join "\n"

    assert_equal expected, @ui.output.chomp
    assert_equal "", @ui.error
  end

  def test_handle_options
    refute @cmd.options[:lib_only]
    assert @cmd.options[:prefix]
    assert_empty @cmd.options[:specdirs]
    assert_nil @cmd.options[:version]
    refute @cmd.options[:show_install_dir]

    @cmd.send :handle_options, %w[
      -l
      -s
      foo
      --version 0.0.2
      --no-prefix
      --show-install-dir
    ]

    assert @cmd.options[:lib_only]
    refute @cmd.options[:prefix]
    assert_equal %w[foo], @cmd.options[:specdirs]
    assert_equal Gem::Requirement.new('0.0.2'), @cmd.options[:version]
    assert @cmd.options[:show_install_dir]
  end
end
