# frozen_string_literal: true

module IRB
  module Command
    class ShowDoc < Base
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
      description "Look up documentation with RI."

      help_message <<~HELP_MESSAGE
        Usage: show_doc [name]

        When name is provided, IRB will look up the documentation for the given name.
        When no name is provided, a RI session will be started.

        Examples:

          show_doc
          show_doc Array
          show_doc Array#each

      HELP_MESSAGE

      def execute(*names)
        require 'rdoc/ri/driver'

        unless ShowDoc.const_defined?(:Ri)
          opts = RDoc::RI::Driver.process_args([])
          ShowDoc.const_set(:Ri, RDoc::RI::Driver.new(opts))
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
end
