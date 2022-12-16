require 'mjit/x86_64/assembler'

class RubyVM::MJIT::Compiler
  # MJIT internals
  Assembler = RubyVM::MJIT::Assembler
  C = RubyVM::MJIT::C

  # Ruby constants
  Qundef = Fiddle::Qundef

  attr_accessor :write_pos

  # @param mem_block [Integer] JIT buffer address
  def initialize(mem_block)
    @mem_block = mem_block
    @write_pos = 0
  end

  # @param iseq [RubyVM::MJIT::CPointer::Struct]
  def compile(iseq)
    return if iseq.body.location.label == '<main>'
    iseq.body.jit_func = compile_iseq(iseq)
  end

  def write_addr
    @mem_block + @write_pos
  end

  private

  # ec -> RDI, cfp -> RSI
  def compile_iseq(iseq)
    addr = write_addr
    asm = Assembler.new

    # pop the current frame (ec->cfp++)
    asm.add(:rsi, C.rb_control_frame_t.size)
    asm.mov([:rdi, C.rb_execution_context_t.offsetof(:cfp)], :rsi)

    # return a value
    asm.mov(:rax, 7)
    asm.ret

    asm.compile(self)
    addr
  end
end
