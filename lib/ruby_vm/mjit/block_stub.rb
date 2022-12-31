class RubyVM::MJIT::BlockStub < Struct.new(
  :iseq, # @param [RubyVM::MJIT::CPointer::Struct_rb_iseq_struct] Jump target ISEQ
  :pc,   # @param [Integer] Jump target pc
  :ctx,  # @param [RubyVM::MJIT::Context] Jump target context
  :addr, # @param [Integer] Jump source address to be re-generated
)
end
