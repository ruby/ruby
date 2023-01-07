class RubyVM::MJIT::BranchStub < Struct.new(
  :iseq,               # @param [RubyVM::MJIT::CPointer::Struct_rb_iseq_struct] Branch target ISEQ
  :ctx,                # @param [RubyVM::MJIT::Context] Branch target context
  :branch_target_pc,   # @param [Integer] Branch target PC
  :branch_target_addr, # @param [Integer] Branch target address
  :branch_target_next, # @param [Proc] Compile branch target next
  :fallthrough_pc,     # @param [Integer] Fallthrough PC
  :fallthrough_addr,   # @param [Integer] Fallthrough address
  :fallthrough_next,   # @param [Proc] Compile fallthrough next
  :neither_next,       # @param [Proc] Compile neither branch target nor fallthrough next
  :start_addr,         # @param [Integer] Stub source start address to be re-generated
  :end_addr,           # @param [Integer] Stub source end address to be re-generated
)
end
