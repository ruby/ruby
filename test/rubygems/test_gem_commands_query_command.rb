# frozen_string_literal: false
require 'rubygems/test_case'
require 'rubygems/commands/query_command'

module TestGemCommandsQueryCommandSetup
  def setup
    super

    @cmd = Gem::Commands::QueryCommand.new

    @specs = add_gems_to_fetcher

    @fetcher.data["#{@gem_repo}Marshal.#{Gem.marshal_version}"] = proc do
      raise Gem::RemoteFetcher::FetchError
    end
  end
end

class TestGemCommandsQueryCommandWithInstalledGems < Gem::TestCase
  include TestGemCommandsQueryCommandSetup

  def test_execute
    spec_fetcher do |fetcher|
      fetcher.legacy_platform
    end

    @cmd.handle_options %w[-r]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF

*** REMOTE GEMS ***

a (2)
pl (1 i386-linux)
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_all
    spec_fetcher do |fetcher|
      fetcher.legacy_platform
    end

    @cmd.handle_options %w[-r --all]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF

*** REMOTE GEMS ***

a (2, 1)
pl (1 i386-linux)
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_all_prerelease
    spec_fetcher do |fetcher|
      fetcher.legacy_platform
    end

    @cmd.handle_options %w[-r --all --prerelease]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF

*** REMOTE GEMS ***

a (3.a, 2, 1)
pl (1 i386-linux)
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_details
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2 do |s|
        s.summary = 'This is a lot of text. ' * 4
        s.authors = ['Abraham Lincoln', 'Hirohito']
        s.homepage = 'http://a.example.com/'
      end

      fetcher.legacy_platform
    end

    @cmd.handle_options %w[-r -d]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF

*** REMOTE GEMS ***

a (2)
    Authors: Abraham Lincoln, Hirohito
    Homepage: http://a.example.com/

    This is a lot of text. This is a lot of text. This is a lot of text.
    This is a lot of text.

pl (1)
    Platform: i386-linux
    Author: A User
    Homepage: http://example.com

    this is a summary
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_installed
    @cmd.handle_options %w[-n a --installed]

    assert_raises Gem::MockGemUi::SystemExitException do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal "true\n", @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_installed_inverse
    @cmd.handle_options %w[-n a --no-installed]

    e = assert_raises Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal "false\n", @ui.output
    assert_equal '', @ui.error

    assert_equal 1, e.exit_code
  end

  def test_execute_installed_inverse_not_installed
    @cmd.handle_options %w[-n not_installed --no-installed]

    assert_raises Gem::MockGemUi::SystemExitException do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal "true\n", @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_installed_no_name
    @cmd.handle_options %w[--installed]

    e = assert_raises Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal '', @ui.output
    assert_equal "ERROR:  You must specify a gem name\n", @ui.error

    assert_equal 4, e.exit_code
  end

  def test_execute_installed_not_installed
    @cmd.handle_options %w[-n not_installed --installed]

    e = assert_raises Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal "false\n", @ui.output
    assert_equal '', @ui.error

    assert_equal 1, e.exit_code
  end

  def test_execute_installed_version
    @cmd.handle_options %w[-n a --installed --version 2]

    assert_raises Gem::MockGemUi::SystemExitException do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal "true\n", @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_installed_version_not_installed
    @cmd.handle_options %w[-n c --installed --version 2]

    e = assert_raises Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal "false\n", @ui.output
    assert_equal '', @ui.error

    assert_equal 1, e.exit_code
  end

  def test_execute_local
    spec_fetcher do |fetcher|
      fetcher.legacy_platform
    end

    @cmd.options[:domain] = :local

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF

*** LOCAL GEMS ***

a (3.a, 2, 1)
pl (1 i386-linux)
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_local_notty
    spec_fetcher do |fetcher|
      fetcher.legacy_platform
    end

    @cmd.handle_options %w[]

    @ui.outs.tty = false

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
a (3.a, 2, 1)
pl (1 i386-linux)
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_local_quiet
    spec_fetcher do |fetcher|
      fetcher.legacy_platform
    end

    @cmd.options[:domain] = :local
    Gem.configuration.verbose = false

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
a (3.a, 2, 1)
pl (1 i386-linux)
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_no_versions
    spec_fetcher do |fetcher|
      fetcher.legacy_platform
    end

    @cmd.handle_options %w[-r --no-versions]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF

*** REMOTE GEMS ***

a
pl
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_notty
    spec_fetcher do |fetcher|
      fetcher.legacy_platform
    end

    @cmd.handle_options %w[-r]

    @ui.outs.tty = false

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
a (2)
pl (1 i386-linux)
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_prerelease
    @cmd.handle_options %w[-r --prerelease]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF

*** REMOTE GEMS ***

a (3.a)
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_prerelease_local
    spec_fetcher do |fetcher|
      fetcher.legacy_platform
    end

    @cmd.handle_options %w[-l --prerelease]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF

*** LOCAL GEMS ***

a (3.a, 2, 1)
pl (1 i386-linux)
    EOF

    assert_equal expected, @ui.output
    assert_equal "WARNING:  prereleases are always shown locally\n", @ui.error
  end

  def test_execute_remote
    spec_fetcher do |fetcher|
      fetcher.legacy_platform
    end

    @cmd.options[:domain] = :remote

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF

*** REMOTE GEMS ***

a (2)
pl (1 i386-linux)
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_remote_notty
    spec_fetcher do |fetcher|
      fetcher.legacy_platform
    end

    @cmd.handle_options %w[]

    @ui.outs.tty = false

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
a (3.a, 2, 1)
pl (1 i386-linux)
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_remote_quiet
    spec_fetcher do |fetcher|
      fetcher.legacy_platform
    end

    @cmd.options[:domain] = :remote
    Gem.configuration.verbose = false

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
a (2)
pl (1 i386-linux)
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_make_entry
    a_2_name = @specs['a-2'].original_name

    @fetcher.data.delete \
      "#{@gem_repo}quick/Marshal.#{Gem.marshal_version}/#{a_2_name}.gemspec.rz"

    a2 = @specs['a-2']
    entry_tuples = [
      [Gem::NameTuple.new(a2.name, a2.version, a2.platform),
       Gem.sources.first],
    ]

    platforms = { a2.version => [a2.platform] }

    entry = @cmd.send :make_entry, entry_tuples, platforms

    assert_equal 'a (2)', entry
  end

  # Test for multiple args handling!
  def test_execute_multiple_args
    spec_fetcher do |fetcher|
      fetcher.legacy_platform
    end

    @cmd.handle_options %w[a pl]

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r%^a %, @ui.output
    assert_match %r%^pl %, @ui.output
    assert_equal '', @ui.error
  end

  def test_show_gems
    @cmd.options[:name] = //
    @cmd.options[:domain] = :remote

    use_ui @ui do
      @cmd.send :show_gems, /a/i, false
    end

    assert_match %r%^a %,  @ui.output
    refute_match %r%^pl %, @ui.output
    assert_empty @ui.error
  end

  private

  def add_gems_to_fetcher
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.spec 'a', 2
      fetcher.spec 'a', '3.a'
    end
  end
end

class TestGemCommandsQueryCommandWithoutInstalledGems < Gem::TestCase
  include TestGemCommandsQueryCommandSetup

  def test_execute_platform
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.spec 'a', 1 do |s|
        s.platform = 'x86-linux'
      end

      fetcher.spec 'a', 2 do |s|
        s.platform = 'universal-darwin'
      end
    end

    @cmd.handle_options %w[-r -a]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF

*** REMOTE GEMS ***

a (2 universal-darwin, 1 ruby x86-linux)
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_default_details
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2
    end

    a1 = new_default_spec 'a', 1
    install_default_specs a1

    @cmd.handle_options %w[-l -d]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF

*** LOCAL GEMS ***

a (2, 1)
    Author: A User
    Homepage: http://example.com
    Installed at (2): #{@gemhome}
                 (1, default): #{a1.base_dir}

    this is a summary
    EOF

    assert_equal expected, @ui.output
  end

  def test_execute_local_details
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1 do |s|
        s.platform = 'x86-linux'
      end

      fetcher.spec 'a', 2 do |s|
        s.summary = 'This is a lot of text. ' * 4
        s.authors = ['Abraham Lincoln', 'Hirohito']
        s.homepage = 'http://a.example.com/'
        s.platform = 'universal-darwin'
      end

      fetcher.legacy_platform
    end

    @cmd.handle_options %w[-l -d]

    use_ui @ui do
      @cmd.execute
    end

    str = @ui.output

    str.gsub!(/\(\d\): [^\n]*/, "-")
    str.gsub!(/at: [^\n]*/, "at: -")

    expected = <<-EOF

*** LOCAL GEMS ***

a (2, 1)
    Platforms:
        1: x86-linux
        2: universal-darwin
    Authors: Abraham Lincoln, Hirohito
    Homepage: http://a.example.com/
    Installed at -
                 -

    This is a lot of text. This is a lot of text. This is a lot of text.
    This is a lot of text.

pl (1)
    Platform: i386-linux
    Author: A User
    Homepage: http://example.com
    Installed at: -

    this is a summary
    EOF

    assert_equal expected, @ui.output
  end

  private

  def add_gems_to_fetcher
    spec_fetcher do |fetcher|
      fetcher.download 'a', 1
      fetcher.download 'a', 2
      fetcher.download 'a', '3.a'
    end
  end
end
