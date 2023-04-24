# frozen_string_literal: false
#
#   help.rb - helper using ri
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

        unless self.class.const_defined?(:Ri)
          opts = RDoc::RI::Driver.process_args([])
          self.class.const_set(:Ri, RDoc::RI::Driver.new(opts))
        end

        if names.empty?
          Ri.interactive
        else
          names.each do |name|
            begin
              Ri.display_name(name.to_s)
            rescue RDoc::RI::Error
              puts $!.message
            end
          end
        end

        nil
      rescue LoadError, SystemExit
        warn "Can't display document because `rdoc` is not installed."
      end
    end
  end

  # :startdoc:
end
