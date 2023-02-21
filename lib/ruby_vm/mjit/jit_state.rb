module RubyVM::MJIT
  class JITState < Struct.new(
    :iseq,                        # @param `RubyVM::MJIT::CPointer::Struct_rb_iseq_t`
    :pc,                          # @param [Integer] The JIT target PC
    :cfp,                         # @param `RubyVM::MJIT::CPointer::Struct_rb_control_frame_t` The JIT source CFP (before MJIT is called)
    :block,                       # @param [RubyVM::MJIT::Block]
    :side_exits,                  # @param [Hash{ Integer => Integer }] { PC => address }
    :record_boundary_patch_point, # @param [TrueClass,FalseClass]
  )
    def initialize(side_exits: {}, record_boundary_patch_point: false, **) = super

    def insn
      Compiler.decode_insn(C.VALUE.new(pc).*)
    end

    def operand(index, signed: false, ruby: false)
      addr = pc + (index + 1) * Fiddle::SIZEOF_VOIDP
      value = Fiddle::Pointer.new(addr)[0, Fiddle::SIZEOF_VOIDP].unpack(signed ? 'q' : 'Q')[0]
      if ruby
        value = C.to_ruby(value)
      end
      value
    end

    def at_current_insn?
      pc == cfp.pc.to_i
    end

    def peek_at_stack(depth_from_top)
      raise 'not at current insn' unless at_current_insn?
      offset = -(1 + depth_from_top)
      # rb_mjit_branch_stub_hit updates SP, so you don't need to worry about sp_offset
      value = (cfp.sp + offset).*
      C.to_ruby(value)
    end

    def peek_at_self
      C.to_ruby(cfp.self)
    end
  end
end
