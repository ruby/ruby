class RubyVM::MJIT::Compiler
  INSNS = RubyVM::MJIT.const_get(:INSNS, false)

  def initialize = freeze

  # @param iseq [RubyVM::MJIT::CPointer::Struct]
  def compile(iseq)
    # TODO: implement
  end
end
