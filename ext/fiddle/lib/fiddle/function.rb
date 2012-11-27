module Fiddle
  class Function
    # The ABI of the Function.
    attr_reader :abi

    # The address of this function
    attr_reader :ptr

    def to_i
      ptr.to_i
    end
  end
end
