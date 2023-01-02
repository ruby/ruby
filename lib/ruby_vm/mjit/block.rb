class RubyVM::MJIT::Block < Struct.new(
  :pc,         # @param [Integer] Starting PC
  :start_addr, # @param [Integer] Starting address of this block's JIT code
  :entry_exit, # @param [Integer] Address of entry exit (optional)
)
end
