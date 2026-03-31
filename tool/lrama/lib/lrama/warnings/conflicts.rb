# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Warnings
    class Conflicts
      # @rbs (Lrama::Logger logger, bool warnings) -> void
      def initialize(logger, warnings)
        @logger = logger
        @warnings = warnings
      end

      # @rbs (Lrama::States states) -> void
      def warn(states)
        return unless @warnings

        if states.sr_conflicts_count != 0
          @logger.warn("shift/reduce conflicts: #{states.sr_conflicts_count} found")
        end

        if states.rr_conflicts_count != 0
          @logger.warn("reduce/reduce conflicts: #{states.rr_conflicts_count} found")
        end
      end
    end
  end
end
