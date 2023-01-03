module RubyVM::MJIT
  class JITState < Struct.new(
    :iseq,       # @param `RubyVM::MJIT::CPointer::Struct_rb_iseq_t`
    :pc,         # @param [Integer] The JIT target PC
    :cfp,        # @param `RubyVM::MJIT::CPointer::Struct_rb_control_frame_t` The JIT source CFP (before MJIT is called)
    :block,      # @param [RubyVM::MJIT::Block]
    :side_exits, # @param [Hash{ Integer => Integer }] { PC => address }
  )
    def initialize(side_exits: {}, **) = super

    def operand(index)
      C.VALUE.new(pc)[index + 1]
    end

    def at_current_insn?
      pc == cfp.pc.to_i
    end

    def peek_at_stack(offset_from_top)
      raise 'not at current insn' unless at_current_insn?
      offset = -(1 + offset_from_top)
      value = (cfp.sp + offset).*
      C.to_ruby(value)
    end
  end
end
