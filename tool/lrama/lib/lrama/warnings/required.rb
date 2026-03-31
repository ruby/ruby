# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Warnings
    class Required
      # @rbs (Lrama::Logger logger, bool warnings) -> void
      def initialize(logger, warnings = false, **_)
        @logger = logger
        @warnings = warnings
      end

      # @rbs (Lrama::Grammar grammar) -> void
      def warn(grammar)
        return unless @warnings

        if grammar.required
          @logger.warn("currently, %require is simply valid as a grammar but does nothing")
        end
      end
    end
  end
end
