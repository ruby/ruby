class RubyVM::MJIT::Compiler
  C = RubyVM::MJIT.const_get(:C, false)
  INSNS = RubyVM::MJIT.const_get(:INSNS, false)

  # @param mem_block [Integer] JIT buffer address
  def initialize(mem_block)
    @mem_block = mem_block
    @write_pos = 0
  end

  # @param iseq [RubyVM::MJIT::CPointer::Struct]
  def compile(iseq)
    # TODO: implement
  end
end
