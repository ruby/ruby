module RubyVM::MJIT
  class JITState < Struct.new(
    :pc, # @param [Integer]
  )
    def operand(index)
      C.VALUE.new(pc)[index + 1]
    end
  end
end
