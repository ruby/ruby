module RubyVM::RJIT
  class JITState < Struct.new(
    :iseq,                        # @param `RubyVM::RJIT::CPointer::Struct_rb_iseq_t`
    :pc,                          # @param [Integer] The JIT target PC
    :cfp,                         # @param `RubyVM::RJIT::CPointer::Struct_rb_control_frame_t` The JIT source CFP (before RJIT is called)
    :block,                       # @param [RubyVM::RJIT::Block]
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
      # rb_rjit_branch_stub_hit updates SP, so you don't need to worry about sp_offset
      value = (cfp.sp + offset).*
      C.to_ruby(value)
    end

    def peek_at_self
      C.to_ruby(cfp.self)
    end

    def peek_at_block_handler(level)
      ep = ep_at_level(cfp, level:)
      ep[C.VM_ENV_DATA_INDEX_SPECVAL]
    end

    private

    def ep_at_level(cfp, level:)
      ep = cfp.ep
      level.times do
        # VM_ENV_PREV_EP
        ep = C.VALUE.new(ep[C.VM_ENV_DATA_INDEX_SPECVAL] & ~0x03)
      end
      ep
    end
  end
end
