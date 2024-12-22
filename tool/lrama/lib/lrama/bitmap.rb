# frozen_string_literal: true

module Lrama
  module Bitmap
    def self.from_array(ary)
      bit = 0

      ary.each do |int|
        bit |= (1 << int)
      end

      bit
    end

    def self.to_array(int)
      a = [] #: Array[Integer]
      i = 0

      while int > 0 do
        if int & 1 == 1
          a << i
        end

        i += 1
        int >>= 1
      end

      a
    end
  end
end
