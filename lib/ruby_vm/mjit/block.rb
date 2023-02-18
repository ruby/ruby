class RubyVM::MJIT::Block < Struct.new(
  :pc,         # @param [Integer] Starting PC
  :ctx,        # @param [RubyVM::MJIT::Context] **Starting** Context (TODO: freeze?)
  :start_addr, # @param [Integer] Starting address of this block's JIT code
  :entry_exit, # @param [Integer] Address of entry exit (optional)
  :incoming,   # @param [Array<RubyVM::MJIT::BranchStub>] Incoming branches
)
  def initialize(incoming: [], **) = super
end
