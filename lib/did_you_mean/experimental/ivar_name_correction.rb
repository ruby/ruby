# frozen-string-literal: true

require_relative '../../did_you_mean'

module DidYouMean
  module Experimental #:nodoc:
    class IvarNameCheckerBuilder #:nodoc:
      attr_reader :original_checker

      def initialize(original_checker) #:nodoc:
        @original_checker = original_checker
      end

      def new(no_method_error) #:nodoc:
        IvarNameChecker.new(no_method_error, original_checker: @original_checker)
      end
    end

    class IvarNameChecker #:nodoc:
      REPLS = {
        "(irb)" => -> { Readline::HISTORY.to_a.last }
      }

      TRACE = TracePoint.trace(:raise) do |tp|
        e = tp.raised_exception

        if SPELL_CHECKERS.include?(e.class.to_s) && !e.instance_variable_defined?(:@frame_binding)
          e.instance_variable_set(:@frame_binding, tp.binding)
        end
      end

      attr_reader :original_checker

      def initialize(no_method_error, original_checker: )
        @original_checker = original_checker.new(no_method_error)

        @location   = no_method_error.backtrace_locations.first
        @ivar_names = no_method_error.frame_binding.receiver.instance_variables

        no_method_error.remove_instance_variable(:@frame_binding)
      end

      def corrections
        original_checker.corrections + ivar_name_corrections
      end

      def ivar_name_corrections
        @ivar_name_corrections ||= SpellChecker.new(dictionary: @ivar_names).correct(receiver_name.to_s)
      end

      private

      def receiver_name
        return unless @original_checker.receiver.nil?

        abs_path = @location.absolute_path
        lineno   = @location.lineno

        /@(\w+)*\.#{@original_checker.method_name}/ =~ line(abs_path, lineno).to_s && $1
      end

      def line(abs_path, lineno)
        if REPLS[abs_path]
          REPLS[abs_path].call
        elsif File.exist?(abs_path)
          File.open(abs_path) do |file|
            file.detect { file.lineno == lineno }
          end
        end
      end
    end
  end

  NameError.send(:attr, :frame_binding)
  SPELL_CHECKERS['NoMethodError'] = Experimental::IvarNameCheckerBuilder.new(SPELL_CHECKERS['NoMethodError'])
end
