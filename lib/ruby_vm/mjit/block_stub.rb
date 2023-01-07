class RubyVM::MJIT::BlockStub < Struct.new(
  :iseq,       # @param [RubyVM::MJIT::CPointer::Struct_rb_iseq_struct] Stub target ISEQ
  :ctx,        # @param [RubyVM::MJIT::Context] Stub target context
  :pc,         # @param [Integer] Stub target pc
  :start_addr, # @param [Integer] Stub source start address to be re-generated
  :end_addr,   # @param [Integer] Stub source end address to be re-generated
)
end
