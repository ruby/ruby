# frozen_string_literal: true
#
#   nop.rb -
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

module IRB
  # :stopdoc:

  module Command
    class CommandArgumentError < StandardError; end

    class Base
      class << self
        def category(category = nil)
          @category = category if category
          @category
        end

        def description(description = nil)
          @description = description if description
          @description
        end

        def help_message(help_message = nil)
          @help_message = help_message if help_message
          @help_message
        end

        private

        def string_literal?(args)
          sexp = Ripper.sexp(args)
          sexp && sexp.size == 2 && sexp.last&.first&.first == :string_literal
        end

        def highlight(text)
          Color.colorize(text, [:BOLD, :BLUE])
        end
      end

      def self.execute(irb_context, *opts, **kwargs, &block)
        command = new(irb_context)
        command.execute(*opts, **kwargs, &block)
      rescue CommandArgumentError => e
        puts e.message
      end

      def initialize(irb_context)
        @irb_context = irb_context
      end

      attr_reader :irb_context

      def execute(*opts)
        #nop
      end
    end

    Nop = Base
  end

  # :startdoc:
end
