# frozen_string_literal: false
#
#   nop.rb -
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

module IRB
  # :stopdoc:

  module ExtendCommand
    class CommandArgumentError < StandardError; end

    class Nop
      class << self
        def category(category = nil)
          @category = category if category
          @category
        end

        def description(description = nil)
          @description = description if description
          @description
        end

        private

        def string_literal?(args)
          sexp = Ripper.sexp(args)
          sexp && sexp.size == 2 && sexp.last&.first&.first == :string_literal
        end
      end

      def self.execute(conf, *opts, **kwargs, &block)
        command = new(conf)
        command.execute(*opts, **kwargs, &block)
      rescue CommandArgumentError => e
        puts e.message
      end

      def initialize(conf)
        @irb_context = conf
      end

      attr_reader :irb_context

      def irb
        @irb_context.irb
      end

      def execute(*opts)
        #nop
      end
    end
  end

  # :startdoc:
end
