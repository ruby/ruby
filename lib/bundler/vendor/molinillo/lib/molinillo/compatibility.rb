# frozen_string_literal: true

module Bundler::Molinillo
  # Hacks needed for old Ruby versions.
  module Compatibility
    module_function

    if [].respond_to?(:flat_map)
      # Flat map
      # @param [Enumerable] enum an enumerable object
      # @block the block to flat-map with
      # @return The enum, flat-mapped
      def flat_map(enum, &blk)
        enum.flat_map(&blk)
      end
    else
      # Flat map
      # @param [Enumerable] enum an enumerable object
      # @block the block to flat-map with
      # @return The enum, flat-mapped
      def flat_map(enum, &blk)
        enum.map(&blk).flatten(1)
      end
    end
  end
end
