#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems'
require 'rubygems/command_manager'
require 'rubygems/config_file'

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
    # TODO: nuke these options
    @command_manager_class = options[:command_manager] || Gem::CommandManager
    @config_file_class = options[:config_file] || Gem::ConfigFile
  end

  ##
  # Run the gem command with the following arguments.

  def run(args)
    if args.include?('--')
      # We need to preserve the original ARGV to use for passing gem options
      # to source gems.  If there is a -- in the line, strip all options after
      # it...its for the source building process.
      # TODO use slice!
      build_args = args[args.index("--") + 1...args.length]
      args = args[0...args.index("--")]
    end

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

  private

  def do_configuration(args)
    Gem.configuration = @config_file_class.new(args)
    Gem.use_paths Gem.configuration[:gemhome], Gem.configuration[:gempath]
    Gem::Command.extra_args = Gem.configuration[:gem]
  end

end

Gem.load_plugins
