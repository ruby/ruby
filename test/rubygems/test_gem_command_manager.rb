require 'rubygems/test_case'
require 'rubygems/command_manager'

class TestGemCommandManager < Gem::TestCase

  def setup
    super

    @command_manager = Gem::CommandManager.new
  end

  def test_find_command
    command = @command_manager.find_command 'install'

    assert_kind_of Gem::Commands::InstallCommand, command

    command = @command_manager.find_command 'ins'

    assert_kind_of Gem::Commands::InstallCommand, command
  end

  def test_find_command_ambiguous
    e = assert_raises Gem::CommandLineError do
      @command_manager.find_command 'u'
    end

    assert_equal 'Ambiguous command u matches [uninstall, unpack, update]',
                 e.message
  end

  def test_find_command_ambiguous_exact
    ins_command = Class.new
    Gem::Commands.send :const_set, :InsCommand, ins_command

    @command_manager.register_command :ins

    command = @command_manager.find_command 'ins'

    assert_kind_of ins_command, command
  ensure
    Gem::Commands.send :remove_const, :InsCommand
  end

  def test_find_command_unknown
    e = assert_raises Gem::CommandLineError do
      @command_manager.find_command 'xyz'
    end

    assert_equal 'Unknown command xyz', e.message
  end

  def test_run_interrupt
    old_load_path = $:.dup
    $: << File.expand_path("test/rubygems", @@project_dir)
    Gem.load_env_plugins

    @command_manager.register_command :interrupt

    use_ui @ui do
      assert_raises Gem::MockGemUi::TermError do
        @command_manager.run %w[interrupt]
      end
      assert_equal '', ui.output
      assert_equal "ERROR:  Interrupted\n", ui.error
    end
  ensure
    $:.replace old_load_path
    Gem::CommandManager.reset
  end

  def test_run_crash_command
    old_load_path = $:.dup
    $: << File.expand_path("test/rubygems", @@project_dir)

    @command_manager.register_command :crash
    use_ui @ui do
      assert_raises Gem::MockGemUi::TermError do
        @command_manager.run %w[crash]
      end
      assert_equal '', ui.output
      err = ui.error.split("\n").first
      assert_equal "ERROR:  Loading command: crash (RuntimeError)", err
    end
  ensure
    $:.replace old_load_path
    @command_manager.unregister_command :crash
  end

  def test_process_args_bad_arg
    use_ui @ui do
      assert_raises Gem::MockGemUi::TermError do
        @command_manager.process_args %w[--bad-arg]
      end
    end

    assert_match(/invalid option: --bad-arg/i, @ui.error)
  end

  # HACK move to install command test
  def test_process_args_install
    #capture all install options
    use_ui @ui do
      check_options = nil
      @command_manager['install'].when_invoked do |options|
        check_options = options
        true
      end

      #check defaults
      @command_manager.process_args %w[install]
      assert_equal %w[ri], check_options[:document].sort
      assert_equal false, check_options[:force]
      assert_equal :both, check_options[:domain]
      assert_equal true, check_options[:wrappers]
      assert_equal Gem::Requirement.default, check_options[:version]
      assert_equal nil, check_options[:install_dir]
      assert_equal nil, check_options[:bin_dir]

      #check settings
      check_options = nil
      @command_manager.process_args %w[
        install --force --local --rdoc --install-dir .
                --version 3.0 --no-wrapper --bindir .
      ]
      assert_equal %w[rdoc ri], check_options[:document].sort
      assert_equal true, check_options[:force]
      assert_equal :local, check_options[:domain]
      assert_equal false, check_options[:wrappers]
      assert_equal Gem::Requirement.new('3.0'), check_options[:version]
      assert_equal Dir.pwd, check_options[:install_dir]
      assert_equal Dir.pwd, check_options[:bin_dir]

      #check remote domain
      check_options = nil
      @command_manager.process_args %w[install --remote]
      assert_equal :remote, check_options[:domain]

      #check both domain
      check_options = nil
      @command_manager.process_args %w[install --both]
      assert_equal :both, check_options[:domain]

      #check both domain
      check_options = nil
      @command_manager.process_args %w[install --both]
      assert_equal :both, check_options[:domain]
    end
  end

  # HACK move to uninstall command test
  def test_process_args_uninstall
    #capture all uninstall options
    check_options = nil
    @command_manager['uninstall'].when_invoked do |options|
      check_options = options
      true
    end

    #check defaults
    @command_manager.process_args %w[uninstall]
    assert_equal Gem::Requirement.default, check_options[:version]

    #check settings
    check_options = nil
    @command_manager.process_args %w[uninstall foobar --version 3.0]
    assert_equal "foobar", check_options[:args].first
    assert_equal Gem::Requirement.new('3.0'), check_options[:version]
  end

  # HACK move to check command test
  def test_process_args_check
    #capture all check options
    check_options = nil
    @command_manager['check'].when_invoked do |options|
      check_options = options
      true
    end

    #check defaults
    @command_manager.process_args %w[check]
    assert_equal true, check_options[:alien]

    #check settings
    check_options = nil
    @command_manager.process_args %w[check foobar --alien]
    assert_equal true, check_options[:alien]
  end

  # HACK move to build command test
  def test_process_args_build
    #capture all build options
    check_options = nil
    @command_manager['build'].when_invoked do |options|
      check_options = options
      true
    end

    #check defaults
    @command_manager.process_args %w[build]
    #NOTE: Currently no defaults

    #check settings
    check_options = nil
    @command_manager.process_args %w[build foobar.rb]
    assert_equal 'foobar.rb', check_options[:args].first
  end

  # HACK move to query command test
  def test_process_args_query
    #capture all query options
    check_options = nil
    @command_manager['query'].when_invoked do |options|
      check_options = options
      true
    end

    #check defaults
    @command_manager.process_args %w[query]
    assert_equal(//, check_options[:name])
    assert_equal :local, check_options[:domain]
    assert_equal false, check_options[:details]

    #check settings
    check_options = nil
    @command_manager.process_args %w[query --name foobar --local --details]
    assert_equal(/foobar/i, check_options[:name])
    assert_equal :local, check_options[:domain]
    assert_equal true, check_options[:details]

    #remote domain
    check_options = nil
    @command_manager.process_args %w[query --remote]
    assert_equal :remote, check_options[:domain]

    #both (local/remote) domains
    check_options = nil
    @command_manager.process_args %w[query --both]
    assert_equal :both, check_options[:domain]
  end

  # HACK move to update command test
  def test_process_args_update
    #capture all update options
    check_options = nil
    @command_manager['update'].when_invoked do |options|
      check_options = options
      true
    end

    #check defaults
    @command_manager.process_args %w[update]
    assert_includes check_options[:document], 'rdoc'

    #check settings
    check_options = nil
    @command_manager.process_args %w[update --force --rdoc --install-dir .]
    assert_includes check_options[:document], 'ri'
    assert_equal true, check_options[:force]
    assert_equal Dir.pwd, check_options[:install_dir]
  end

end

