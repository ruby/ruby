# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Counterexamples
    class Path
      # @rbs!
      #   @state_item: StateItem
      #   @parent: Path?

      attr_reader :state_item #: StateItem
      attr_reader :parent #: Path?

      # @rbs (StateItem state_item, Path? parent) -> void
      def initialize(state_item, parent)
        @state_item = state_item
        @parent = parent
      end

      # @rbs () -> ::String
      def to_s
        "#<Path>"
      end
      alias :inspect :to_s
    end
  end
end
