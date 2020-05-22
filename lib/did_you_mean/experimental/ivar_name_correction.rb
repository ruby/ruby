# frozen-string-literal: true

require_relative '../../did_you_mean/spell_checker'
require_relative '../../did_you_mean/spell_checkers/method_name_checker'

module DidYouMean
  module Experimental #:nodoc:
    class IvarNameChecker < ::DidYouMean::MethodNameChecker #:nodoc:
      REPLS = {
        "(irb)" => -> { Readline::HISTORY.to_a.last }
      }

      TRACE = TracePoint.trace(:raise) do |tp|
        e = tp.raised_exception

        if SPELL_CHECKERS.include?(e.class.to_s) && !e.instance_variable_defined?(:@frame_binding)
          e.instance_variable_set(:@frame_binding, tp.binding)
        end
      end

      attr_reader :location, :ivar_names

      def initialize(no_method_error)
        super(no_method_error)

        @location   = no_method_error.backtrace_locations.first
        @ivar_names = no_method_error.frame_binding.receiver.instance_variables

        no_method_error.remove_instance_variable(:@frame_binding)
      end

      def corrections
        super + ivar_name_corrections
      end

      def ivar_name_corrections
        @ivar_name_corrections ||= SpellChecker.new(dictionary: ivar_names).correct(receiver_name.to_s)
      end

      private

      def receiver_name
        return unless receiver.nil?

        abs_path = location.absolute_path
        lineno   = location.lineno

        /@(\w+)*\.#{method_name}/ =~ line(abs_path, lineno).to_s && $1
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

  NoMethodError.send(:attr, :frame_binding)
  SPELL_CHECKERS['NoMethodError'] = Experimental::IvarNameChecker
end
