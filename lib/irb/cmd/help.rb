# frozen_string_literal: false
#
#   help.rb - helper using ri
#   	$Release Version: 0.9.6$
#   	$Revision$
#
# --
#
#
#

require_relative "nop"

module IRB
  # :stopdoc:

  module ExtendCommand
    class Help < Nop
      class << self
        def transform_args(args)
          # Return a string literal as is for backward compatibility
          if args.empty? || string_literal?(args)
            args
          else # Otherwise, consider the input as a String for convenience
            args.strip.dump
          end
        end
      end

      category "Context"
      description "Enter the mode to look up RI documents."

      def execute(*names)
        require 'rdoc/ri/driver'
        opts = RDoc::RI::Driver.process_args([])
        IRB::ExtendCommand::Help.const_set(:Ri, RDoc::RI::Driver.new(opts))
      rescue LoadError, SystemExit
        IRB::ExtendCommand::Help.remove_method(:execute)
        # raise NoMethodError in ensure
      else
        def execute(*names)
          if names.empty?
            Ri.interactive
            return
          end
          names.each do |name|
            begin
              Ri.display_name(name.to_s)
            rescue RDoc::RI::Error
              puts $!.message
            end
          end
          nil
        end
        nil
      ensure
        execute(*names)
      end
    end
  end

  # :startdoc:
end
