# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  module Bitmap
    # @rbs!
    #   type bitmap = Integer

    # @rbs (Array[Integer] ary) -> bitmap
    def self.from_array(ary)
      bit = 0

      ary.each do |int|
        bit |= (1 << int)
      end

      bit
    end

    # @rbs (Integer int) -> bitmap
    def self.from_integer(int)
      1 << int
    end

    # @rbs (bitmap int) -> Array[Integer]
    def self.to_array(int)
      a = [] #: Array[Integer]
      i = 0

      len = int.bit_length
      while i < len do
        if int[i] == 1
          a << i
        end

        i += 1
      end

      a
    end

    # @rbs (bitmap int, Integer size) -> Array[bool]
    def self.to_bool_array(int, size)
      Array.new(size) { |i| int[i] == 1 }
    end
  end
end
