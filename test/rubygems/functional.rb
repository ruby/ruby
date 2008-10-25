#!/usr/bin/env ruby
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems'
require 'minitest/unit'
require 'test/insure_session'
require 'rubygems/format'
require 'rubygems/command_manager'

class FunctionalTest < MiniTest::Unit::TestCase

  def setup
    @gem_path = File.expand_path("bin/gem")
    lib_path = File.expand_path("lib")
    @ruby_options = "-I#{lib_path} -I."
    @verbose = false
  end

  def test_gem_help_options
    gem_nossl 'help options'
    assert_match(/Usage:/, @out, @err)
    assert_status
  end

  def test_gem_help_commands
    gem_nossl 'help commands'
    assert_match(/gem install/, @out)
    assert_status
  end

  def test_gem_no_args_shows_help
    gem_nossl
    assert_match(/Usage:/, @out)
    assert_status 1
  end

  # This test is disabled because of the insanely long time it takes
  # to time out.
  def xtest_bogus_source_hoses_up_remote_install_but_gem_command_gives_decent_error_message
    @ruby_options << " -rtest/bogussources"
    gem_nossl "install asdf --remote"
    assert_match(/error/im, @err)
    assert_status 1
  end

  def test_all_command_helps
    mgr = Gem::CommandManager.new
    mgr.command_names.each do |cmdname|
      gem_nossl "help #{cmdname}"
      assert_match(/Usage: gem #{cmdname}/, @out,
                   "should see help for #{cmdname}")
    end
  end

  # :section: Help Methods

  # Run a gem command without the SSL library.
  def gem_nossl(options="")
    old_options = @ruby_options.dup
    @ruby_options << " -Itest/fake_certlib"
    gem(options)
  ensure
    @ruby_options = old_options
  end

  # Run a gem command with the SSL library.
  def gem_withssl(options="")
    gem(options)
  end

  # Run a gem command for the functional test.
  def gem(options="")
    shell = Session::Shell.new
    options = options + " --config-file missing_file" if options !~ /--config-file/
    command = "#{Gem.ruby} #{@ruby_options} #{@gem_path} #{options}"
    puts "\n\nCOMMAND: [#{command}]" if @verbose
    @out, @err = shell.execute command
    @status = shell.exit_status
    puts "STATUS:  [#{@status}]" if @verbose
    puts "OUTPUT:  [#{@out}]" if @verbose
    puts "ERROR:   [#{@err}]" if @verbose
    puts "PWD:     [#{Dir.pwd}]" if @verbose
    shell.close
  end

  private

  def assert_status(expected_status=0)
    assert_equal expected_status, @status
  end

end

MiniTest::Unit.autorun

