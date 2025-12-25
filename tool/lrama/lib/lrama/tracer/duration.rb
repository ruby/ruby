# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Tracer
    module Duration
      # TODO: rbs-inline 0.11.0 doesn't support instance variables.
      #       Move these type declarations above instance variable definitions, once it's supported.
      #       see: https://github.com/soutaro/rbs-inline/pull/149
      #
      # @rbs!
      #   @_report_duration_enabled: bool

      # @rbs () -> void
      def self.enable
        @_report_duration_enabled = true
      end

      # @rbs () -> bool
      def self.enabled?
        !!@_report_duration_enabled
      end

      # @rbs [T] (_ToS message) { -> T } -> T
      def report_duration(message)
        time1 = Time.now.to_f
        result = yield
        time2 = Time.now.to_f

        if Duration.enabled?
          STDERR.puts sprintf("%s %10.5f s", message, time2 - time1)
        end

        return result
      end
    end
  end
end
