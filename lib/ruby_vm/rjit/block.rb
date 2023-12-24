module RubyVM::RJIT
  class Block < Struct.new(
    :iseq,        # @param iseq `RubyVM::RJIT::CPointer::Struct_rb_iseq_t`
    :pc,          # @param [Integer] Starting PC
    :c_ctx,       # @param [Integer] **Starting** Context
    :start_addr,  # @param [Integer] Starting address of this block's JIT code
    :entry_exit,  # @param [Integer] Address of entry exit (optional)
    :incoming,    # @param [Array<RubyVM::RJIT::BranchStub>] Incoming branches
    :invalidated, # @param [TrueClass,FalseClass] true if already invalidated
  )
    def initialize(ctx:, incoming: [], invalidated: false, **kwargs)
      super(c_ctx: ctx.to_i, incoming:, invalidated:, **kwargs)
    end

    def ctx
      Context.new(c_ctx)
    end
  end
end
