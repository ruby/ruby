# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/commands/update_command'

class TestGemCommandsUpdateCommand < Gem::TestCase

  def setup
    super
    common_installer_setup

    @cmd = Gem::Commands::UpdateCommand.new

    @cmd.options[:document] = []

    @specs = spec_fetcher do |fetcher|
      fetcher.download 'a', 1
      fetcher.download 'a', 2
      fetcher.download 'a', '3.a'
    end

    @a1_path  = @specs['a-1'].cache_file
    @a2_path  = @specs['a-1'].cache_file
    @a3a_path = @specs['a-3.a'].cache_file
  end

  def test_execute
    spec_fetcher do |fetcher|
      fetcher.download 'a', 2
      fetcher.spec 'a', 1
    end

    @cmd.options[:args] = []

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Updating a", out.shift
    assert_equal "Gems updated: a", out.shift
    assert_empty out
  end

  def test_execute_multiple
    spec_fetcher do |fetcher|
      fetcher.download 'a',  2
      fetcher.download 'ab', 2

      fetcher.spec 'a',  1
      fetcher.spec 'ab', 1
    end

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Updating a", out.shift
    assert_equal "Gems updated: a", out.shift
    assert_empty out
  end

  def test_execute_system
    spec_fetcher do |fetcher|
      fetcher.download 'rubygems-update', 9 do |s| s.files = %w[setup.rb] end
    end

    @cmd.options[:args]          = []
    @cmd.options[:system]        = true

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating rubygems-update", out.shift
    assert_equal "Installing RubyGems 9", out.shift
    assert_equal "RubyGems system software updated", out.shift

    assert_empty out
  end

  def test_execute_system_at_latest
    spec_fetcher do |fetcher|
      fetcher.download 'rubygems-update', Gem::VERSION do |s|
        s.files = %w[setup.rb]
      end
    end

    @cmd.options[:args]          = []
    @cmd.options[:system]        = true

    assert_raises Gem::MockGemUi::SystemExitException do
      use_ui @ui do
        @cmd.execute
      end
    end

    out = @ui.output.split "\n"
    assert_equal "Latest version already installed. Done.", out.shift
    assert_empty out
  end

  def test_execute_system_multiple
    spec_fetcher do |fetcher|
      fetcher.download 'rubygems-update', 8 do |s| s.files = %w[setup.rb] end
      fetcher.download 'rubygems-update', 9 do |s| s.files = %w[setup.rb] end
    end

    @cmd.options[:args]          = []
    @cmd.options[:system]        = true

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating rubygems-update", out.shift
    assert_equal "Installing RubyGems 9", out.shift
    assert_equal "RubyGems system software updated", out.shift

    assert_empty out
  end

  def test_execute_system_specific
    spec_fetcher do |fetcher|
      fetcher.download 'rubygems-update', 8 do |s| s.files = %w[setup.rb] end
      fetcher.download 'rubygems-update', 9 do |s| s.files = %w[setup.rb] end
    end

    @cmd.options[:args]          = []
    @cmd.options[:system]        = "8"

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating rubygems-update", out.shift
    assert_equal "Installing RubyGems 8", out.shift
    assert_equal "RubyGems system software updated", out.shift

    assert_empty out
  end

  def test_execute_system_specifically_to_latest_version
    spec_fetcher do |fetcher|
      fetcher.download 'rubygems-update', 8 do |s| s.files = %w[setup.rb] end
      fetcher.download 'rubygems-update', 9 do |s| s.files = %w[setup.rb] end
    end

    @cmd.options[:args]          = []
    @cmd.options[:system]        = "9"

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating rubygems-update", out.shift
    assert_equal "Installing RubyGems 9", out.shift
    assert_equal "RubyGems system software updated", out.shift

    assert_empty out
  end

  def test_execute_system_with_gems
    @cmd.options[:args]          = %w[gem]
    @cmd.options[:system]        = true

    assert_raises Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_empty @ui.output
    assert_equal "ERROR:  Gem names are not allowed with the --system option\n",
                 @ui.error
  end

  # before:
  #   a1 -> c1.2
  # after:
  #   a2 -> b2 # new dependency
  #   a2 -> c2

  def test_execute_dependencies
    spec_fetcher do |fetcher|
      fetcher.download 'a', 2, 'b' => 2, 'c' => 2
      fetcher.download 'b', 2
      fetcher.download 'c', 2

      fetcher.spec 'a', 1, 'c' => '1.2'
      fetcher.spec 'c', '1.2'
    end

    Gem::Specification.reset

    @cmd.options[:args] = []

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Updating a", out.shift
    assert_equal "Gems updated: a b c",
                 out.shift

    assert_empty out
  end

  def test_execute_rdoc
    skip if RUBY_VERSION <= "1.8.7"
    spec_fetcher do |fetcher|
      fetcher.download 'a', 2
      fetcher.spec 'a', 1
    end

    Gem.done_installing(&Gem::RDoc.method(:generation_hook))

    @cmd.options[:document] = %w[rdoc ri]

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    wait_for_child_process_to_exit

    a2 = @specs['a-2']

    assert_path_exists File.join(a2.doc_dir, 'rdoc')
  end

  def test_execute_named
    spec_fetcher do |fetcher|
      fetcher.download 'a', 2

      fetcher.spec 'a', 1
    end

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Updating a", out.shift
    assert_equal "Gems updated: a", out.shift

    assert_empty out
  end

  def test_execute_named_some_up_to_date
    spec_fetcher do |fetcher|
      fetcher.download 'a', 2
      fetcher.spec 'a', 1

      fetcher.spec 'b', 2
    end

    @cmd.options[:args] = %w[a b]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems",    out.shift
    assert_equal "Updating a",                 out.shift
    assert_equal "Gems updated: a",            out.shift
    assert_equal "Gems already up-to-date: b", out.shift

    assert_empty out
  end

  def test_execute_named_up_to_date
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 2
    end

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Nothing to update", out.shift

    assert_empty out
  end

  def test_execute_named_up_to_date_prerelease
    spec_fetcher do |fetcher|
      fetcher.download 'a', '3.a'

      fetcher.gem 'a', 2
    end

    @cmd.options[:args] = %w[a]
    @cmd.options[:prerelease] = true

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Updating a", out.shift
    assert_equal "Gems updated: a", out.shift

    assert_empty out
  end

  def test_execute_up_to_date
    spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
    end

    @cmd.options[:args] = []

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Nothing to update", out.shift

    assert_empty out
  end

  def test_execute_user_install
    spec_fetcher do |fetcher|
      fetcher.download 'a', 2
      fetcher.spec 'a', 1
    end

    @cmd.handle_options %w[--user-install]

    use_ui @ui do
      @cmd.execute
    end

    installer = @cmd.installer
    user_install = installer.instance_variable_get :@user_install

    assert user_install, 'user_install must be set on the installer'
  end

  def test_fetch_remote_gems
    specs = spec_fetcher do |fetcher|
      fetcher.gem 'a', 1
      fetcher.gem 'a', 2
    end

    expected = [
      [Gem::NameTuple.new('a', v(2), Gem::Platform::RUBY),
        Gem::Source.new(@gem_repo)],
    ]

    assert_equal expected, @cmd.fetch_remote_gems(specs['a-1'])
  end

  def test_fetch_remote_gems_error
    Gem.sources.replace %w[http://nonexistent.example]

    assert_raises Gem::RemoteFetcher::FetchError do
      @cmd.fetch_remote_gems @specs['a-1']
    end
  end

  def test_fetch_remote_gems_mismatch
    platform = Gem::Platform.new 'x86-freebsd9'

    specs = spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.spec 'a', 2
      fetcher.spec 'a', 2 do |s| s.platform = platform end
    end

    expected = [
      [Gem::NameTuple.new('a', v(2), Gem::Platform::RUBY),
        Gem::Source.new(@gem_repo)],
    ]

    assert_equal expected, @cmd.fetch_remote_gems(specs['a-1'])
  end

  def test_fetch_remote_gems_prerelease
    specs = spec_fetcher do |fetcher|
      fetcher.gem 'a', 1
      fetcher.gem 'a', 2
      fetcher.gem 'a', '3.a'
    end

    @cmd.options[:prerelease] = true

    expected = [
      [Gem::NameTuple.new('a', v(2), Gem::Platform::RUBY),
        Gem::Source.new(@gem_repo)],
      [Gem::NameTuple.new('a', v('3.a'), Gem::Platform::RUBY),
        Gem::Source.new(@gem_repo)],
    ]

    assert_equal expected, @cmd.fetch_remote_gems(specs['a-1'])
  end

  def test_handle_options_system
    @cmd.handle_options %w[--system]

    expected = {
      :args     => [],
      :document => %w[rdoc ri],
      :force    => false,
      :system   => true,
    }

    assert_equal expected, @cmd.options
  end

  def test_handle_options_system_non_version
    assert_raises ArgumentError do
      @cmd.handle_options %w[--system non-version]
    end
  end

  def test_handle_options_system_specific
    @cmd.handle_options %w[--system 1.3.7]

    expected = {
      :args     => [],
      :document => %w[rdoc ri],
      :force    => false,
      :system   => "1.3.7",
    }

    assert_equal expected, @cmd.options
  end

  def test_update_gem_prerelease
    spec_fetcher do |fetcher|
      fetcher.spec 'a', '1.a'
      fetcher.gem  'a', '1.b'
    end

    @cmd.update_gem 'a', Gem::Requirement.new('= 1.b')

    refute_empty @cmd.updated

    assert @cmd.installer.instance_variable_get :@prerelease
  end

  def test_update_gem_unresolved_dependency
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.gem  'a', 2 do |s|
        s.add_dependency 'b', '>= 2'
      end

      fetcher.spec 'b', 1
    end

    @cmd.update_gem 'a'

    assert_empty @cmd.updated
  end

  def test_update_rubygems_arguments
    @cmd.options[:system] = true

    arguments = @cmd.update_rubygems_arguments

    assert_equal '--prefix',           arguments.shift
    assert_equal Gem.prefix,           arguments.shift
    assert_equal '--no-rdoc',          arguments.shift
    assert_equal '--no-ri',            arguments.shift
    assert_equal '--previous-version', arguments.shift
    assert_equal Gem::VERSION,         arguments.shift
    assert_empty arguments
  end

  def test_update_rubygems_arguments_1_8_x
    @cmd.options[:system] = '1.8.26'

    arguments = @cmd.update_rubygems_arguments

    assert_equal '--prefix',           arguments.shift
    assert_equal Gem.prefix,           arguments.shift
    assert_equal '--no-rdoc',          arguments.shift
    assert_equal '--no-ri',            arguments.shift
    assert_empty arguments
  end

end

