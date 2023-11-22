# frozen_string_literal: true

module IRB
  class Statement
    attr_reader :code

    def is_assignment?
      raise NotImplementedError
    end

    def suppresses_echo?
      raise NotImplementedError
    end

    def should_be_handled_by_debugger?
      raise NotImplementedError
    end

    def evaluable_code
      raise NotImplementedError
    end

    class Expression < Statement
      def initialize(code, is_assignment)
        @code = code
        @is_assignment = is_assignment
      end

      def suppresses_echo?
        @code.match?(/;\s*\z/)
      end

      def should_be_handled_by_debugger?
        true
      end

      def is_assignment?
        @is_assignment
      end

      def evaluable_code
        @code
      end
    end

    class Command < Statement
      def initialize(code, command, arg, command_class)
        @code = code
        @command = command
        @arg = arg
        @command_class = command_class
      end

      def is_assignment?
        false
      end

      def suppresses_echo?
        false
      end

      def should_be_handled_by_debugger?
        require_relative 'cmd/help'
        require_relative 'cmd/debug'
        IRB::ExtendCommand::DebugCommand > @command_class || IRB::ExtendCommand::Help == @command_class
      end

      def evaluable_code
        # Hook command-specific transformation to return valid Ruby code
        if @command_class.respond_to?(:transform_args)
          arg = @command_class.transform_args(@arg)
        else
          arg = @arg
        end

        [@command, arg].compact.join(' ')
      end
    end
  end
end
