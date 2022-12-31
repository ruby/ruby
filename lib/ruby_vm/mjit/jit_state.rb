module RubyVM::MJIT
  class JITState < Struct.new(
    :iseq,
    :pc,  # @param [Integer] The JIT target PC
    :cfp, # @param `RubyVM::MJIT::CPointer::Struct_rb_control_frame_t` The JIT source CFP (before MJIT is called)
  )
    def operand(index)
      C.VALUE.new(pc)[index + 1]
    end

    def at_current_insn?
      pc == cfp.pc.to_i
    end
  end
end
