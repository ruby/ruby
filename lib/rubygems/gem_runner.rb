#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems/command_manager'
require 'rubygems/config_file'
require 'rubygems/doc_manager'

module Gem

  ####################################################################
  # Run an instance of the gem program.
  #
  class GemRunner

    def initialize(options={})
      @command_manager_class = options[:command_manager] || Gem::CommandManager
      @config_file_class = options[:config_file] || Gem::ConfigFile
      @doc_manager_class = options[:doc_manager] || Gem::DocManager
    end

    # Run the gem command with the following arguments.
    def run(args)
      start_time = Time.now
      do_configuration(args)
      cmd = @command_manager_class.instance
      cmd.command_names.each do |command_name|
        config_args = Gem.configuration[command_name]
        config_args = case config_args
                      when String
                        config_args.split ' '
                      else
                        Array(config_args)
                      end
        Command.add_specific_extra_args command_name, config_args
      end
      cmd.run(Gem.configuration.args)
      end_time = Time.now
      if Gem.configuration.benchmark 
        printf "\nExecution time: %0.2f seconds.\n", end_time-start_time
        puts "Press Enter to finish"
        STDIN.gets
      end
    end

    private

    def do_configuration(args)
      Gem.configuration = @config_file_class.new(args)
      Gem.use_paths(Gem.configuration[:gemhome], Gem.configuration[:gempath])
      Gem::Command.extra_args = Gem.configuration[:gem]
      @doc_manager_class.configured_args = Gem.configuration[:rdoc]
    end

  end # class
end # module
