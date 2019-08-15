# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems'
require 'rubygems/command_manager'
require 'rubygems/config_file'
require 'rubygems/deprecate'

##
# Load additional plugins from $LOAD_PATH

Gem.load_env_plugins rescue nil

##
# Run an instance of the gem program.
#
# Gem::GemRunner is only intended for internal use by RubyGems itself.  It
# does not form any public API and may change at any time for any reason.
#
# If you would like to duplicate functionality of `gem` commands, use the
# classes they call directly.

class Gem::GemRunner

  def initialize(options={})
    if !options.empty? && !Gem::Deprecate.skip
      Kernel.warn "NOTE: passing options to Gem::GemRunner.new is deprecated with no replacement. It will be removed on or after 2016-10-01."
    end

    @command_manager_class = options[:command_manager] || Gem::CommandManager
    @config_file_class = options[:config_file] || Gem::ConfigFile
  end

  ##
  # Run the gem command with the following arguments.

  def run(args)
    build_args = extract_build_args args

    do_configuration args

    cmd = @command_manager_class.instance

    cmd.command_names.each do |command_name|
      config_args = Gem.configuration[command_name]
      config_args = case config_args
                    when String
                      config_args.split ' '
                    else
                      Array(config_args)
                    end
      Gem::Command.add_specific_extra_args command_name, config_args
    end

    cmd.run Gem.configuration.args, build_args
  end

  ##
  # Separates the build arguments (those following <code>--</code>) from the
  # other arguments in the list.

  def extract_build_args(args) # :nodoc:
    return [] unless offset = args.index('--')

    build_args = args.slice!(offset...args.length)

    build_args.shift

    build_args
  end

  private

  def do_configuration(args)
    Gem.configuration = @config_file_class.new(args)
    Gem.use_paths Gem.configuration[:gemhome], Gem.configuration[:gempath]
    Gem::Command.extra_args = Gem.configuration[:gem]
  end

end

Gem.load_plugins
