module RubyVM::RJIT
  class Context < Struct.new(
    :stack_size,  # @param [Integer] The number of values on the stack
    :sp_offset,   # @param [Integer] JIT sp offset relative to the interpreter's sp
    :chain_depth, # @param [Integer] jit_chain_guard depth
  )
    def initialize(stack_size: 0, sp_offset: 0, chain_depth: 0) = super

    def stack_push(size = 1)
      self.stack_size += size
      self.sp_offset += size
      stack_opnd(0)
    end

    def stack_pop(size = 1)
      opnd = stack_opnd(0)
      self.stack_size -= size
      self.sp_offset -= size
      opnd
    end

    def stack_opnd(depth_from_top)
      [SP, C.VALUE.size * (self.sp_offset - 1 - depth_from_top)]
    end

    def sp_opnd(offset_bytes = 0)
      [SP, (C.VALUE.size * self.sp_offset) + offset_bytes]
    end

    # Create a new Context instance with a given stack_size and sp_offset adjusted
    # accordingly. This is useful when you want to virtually rewind a stack_size for
    # generating a side exit while considering past sp_offset changes on gen_save_sp.
    def with_stack_size(stack_size)
      ctx = self.dup
      ctx.sp_offset -= ctx.stack_size - stack_size
      ctx.stack_size = stack_size
      ctx
    end
  end
end
