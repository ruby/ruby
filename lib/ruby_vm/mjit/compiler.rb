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

    iseq.body.jit_func = write_addr
    asm = Assembler.new
    asm.mov(:eax, Qundef)
    asm.ret
    asm.compile(self)
  end

  def write_addr
    @mem_block + @write_pos
  end
end
