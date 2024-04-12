# frozen_string_literal: true
#
#   nop.rb -
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

module IRB
  # :stopdoc:

  module Command
    class CommandArgumentError < StandardError; end

    def self.extract_ruby_args(*args, **kwargs)
      throw :EXTRACT_RUBY_ARGS, [args, kwargs]
    end

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

        def highlight(text)
          Color.colorize(text, [:BOLD, :BLUE])
        end
      end

      def self.execute(irb_context, arg)
        new(irb_context).execute(arg)
      rescue CommandArgumentError => e
        puts e.message
      end

      def initialize(irb_context)
        @irb_context = irb_context
      end

      attr_reader :irb_context

      def unwrap_string_literal(str)
        return if str.empty?

        sexp = Ripper.sexp(str)
        if sexp && sexp.size == 2 && sexp.last&.first&.first == :string_literal
          @irb_context.workspace.binding.eval(str).to_s
        else
          str
        end
      end

      def ruby_args(arg)
        # Use throw and catch to handle arg that includes `;`
        # For example: "1, kw: (2; 3); 4" will be parsed to [[1], { kw: 3 }]
        catch(:EXTRACT_RUBY_ARGS) do
          @irb_context.workspace.binding.eval "IRB::Command.extract_ruby_args #{arg}"
        end || [[], {}]
      end

      def execute(arg)
        #nop
      end
    end

    Nop = Base
  end

  # :startdoc:
end
