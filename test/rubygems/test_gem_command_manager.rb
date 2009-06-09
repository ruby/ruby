#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/command_manager'

class TestGemCommandManager < RubyGemTestCase

  def setup
    super

    @command_manager = Gem::CommandManager.instance
  end

  def test_run_interrupt
    use_ui @ui do
      assert_raises MockGemUi::TermError do
        @command_manager.run 'interrupt'
      end
      assert_equal '', ui.output
      assert_equal "ERROR:  Interrupted\n", ui.error
    end
  end

  def test_process_args_bad_arg
    use_ui @ui do
      assert_raises(MockGemUi::TermError) {
        @command_manager.process_args("--bad-arg")
      }
    end

    assert_match(/invalid option: --bad-arg/i, @ui.error)
  end

  def test_process_args_install
    #capture all install options
    use_ui @ui do
      check_options = nil
      @command_manager['install'].when_invoked do |options|
        check_options = options
        true
      end

      #check defaults
      @command_manager.process_args("install")
      assert_equal false, check_options[:test]
      assert_equal true, check_options[:generate_rdoc]
      assert_equal false, check_options[:force]
      assert_equal :both, check_options[:domain]
      assert_equal true, check_options[:wrappers]
      assert_equal Gem::Requirement.default, check_options[:version]
      assert_equal nil, check_options[:install_dir]
      assert_equal nil, check_options[:bin_dir]

      #check settings
      check_options = nil
      @command_manager.process_args(
        "install --force --test --local --rdoc --install-dir . --version 3.0 --no-wrapper --bindir . ")
      assert_equal true, check_options[:test]
      assert_equal true, check_options[:generate_rdoc]
      assert_equal true, check_options[:force]
      assert_equal :local, check_options[:domain]
      assert_equal false, check_options[:wrappers]
      assert_equal Gem::Requirement.new('3.0'), check_options[:version]
      assert_equal Dir.pwd, check_options[:install_dir]
      assert_equal Dir.pwd, check_options[:bin_dir]

      #check remote domain
      check_options = nil
      @command_manager.process_args("install --remote")
      assert_equal :remote, check_options[:domain]

      #check both domain
      check_options = nil
      @command_manager.process_args("install --both")
      assert_equal :both, check_options[:domain]

      #check both domain
      check_options = nil
      @command_manager.process_args("install --both")
      assert_equal :both, check_options[:domain]
    end
  end

  def test_process_args_uninstall
    #capture all uninstall options
    check_options = nil
    @command_manager['uninstall'].when_invoked do |options|
      check_options = options
      true
    end

    #check defaults
    @command_manager.process_args("uninstall")
    assert_equal Gem::Requirement.default, check_options[:version]

    #check settings
    check_options = nil
    @command_manager.process_args("uninstall foobar --version 3.0")
    assert_equal "foobar", check_options[:args].first
    assert_equal Gem::Requirement.new('3.0'), check_options[:version]
  end

  def test_process_args_check
    #capture all check options
    check_options = nil
    @command_manager['check'].when_invoked do |options|
      check_options = options
      true
    end

    #check defaults
    @command_manager.process_args("check")
    assert_equal false, check_options[:verify]
    assert_equal false, check_options[:alien]

    #check settings
    check_options = nil
    @command_manager.process_args("check --verify foobar --alien")
    assert_equal "foobar", check_options[:verify]
    assert_equal true, check_options[:alien]
  end

  def test_process_args_build
    #capture all build options
    check_options = nil
    @command_manager['build'].when_invoked do |options|
      check_options = options
      true
    end

    #check defaults
    @command_manager.process_args("build")
    #NOTE: Currently no defaults

    #check settings
    check_options = nil
    @command_manager.process_args("build foobar.rb")
    assert_equal 'foobar.rb', check_options[:args].first
  end

  def test_process_args_query
    #capture all query options
    check_options = nil
    @command_manager['query'].when_invoked do |options|
      check_options = options
      true
    end

    #check defaults
    @command_manager.process_args("query")
    assert_equal(//, check_options[:name])
    assert_equal :local, check_options[:domain]
    assert_equal false, check_options[:details]

    #check settings
    check_options = nil
    @command_manager.process_args("query --name foobar --local --details")
    assert_equal(/foobar/i, check_options[:name])
    assert_equal :local, check_options[:domain]
    assert_equal true, check_options[:details]

    #remote domain
    check_options = nil
    @command_manager.process_args("query --remote")
    assert_equal :remote, check_options[:domain]

    #both (local/remote) domains
    check_options = nil
    @command_manager.process_args("query --both")
    assert_equal :both, check_options[:domain]
  end

  def test_process_args_update
    #capture all update options
    check_options = nil
    @command_manager['update'].when_invoked do |options|
      check_options = options
      true
    end

    #check defaults
    @command_manager.process_args("update")
    assert_equal true, check_options[:generate_rdoc]

    #check settings
    check_options = nil
    @command_manager.process_args("update --force --test --rdoc --install-dir .")
    assert_equal true, check_options[:test]
    assert_equal true, check_options[:generate_rdoc]
    assert_equal true, check_options[:force]
    assert_equal Dir.pwd, check_options[:install_dir]
  end

end

