module RubyVM::MJIT
  class Context < Struct.new(
    :stack_size,  # @param [Integer] The number of values on the stack
    :sp_offset,   # @param [Integer] JIT sp offset relative to the interpreter's sp
    :chain_depth, # @param [Integer] jit_chain_guard depth
  )
    def initialize(stack_size: 0, sp_offset: 0, chain_depth: 0) = super

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

    def stack_opnd(depth_from_top)
      [SP, C.VALUE.size * (self.sp_offset - 1 - depth_from_top)]
    end

    def sp_opnd(offset_bytes)
      [SP, (C.VALUE.size * self.sp_offset) + offset_bytes]
    end
  end
end
