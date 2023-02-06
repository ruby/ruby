module RubyVM::MJIT
  class Context < Struct.new(
    :stack_size, # @param [Integer] The number of values on the stack
    :sp_offset,  # @param [Integer] JIT sp offset relative to the interpreter's sp
  )
    def initialize(stack_size: 0, sp_offset: 0) = super

    def stack_push(size = 1)
      opnd = [SP, C.VALUE.size * self.sp_offset]
      self.stack_size += size
      self.sp_offset += size
      opnd
    end

    def stack_pop(size = 1)
      self.stack_size -= size
      self.sp_offset -= size
      [SP, C.VALUE.size * self.sp_offset]
    end
  end
end
