module RubyVM::RJIT
  # Branch shapes
  Next0   = :Next0   # target0 is a fallthrough
  Next1   = :Next1   # target1 is a fallthrough
  Default = :Default # neither targets is a fallthrough

  class BranchStub < Struct.new(
    :iseq,       # @param [RubyVM::RJIT::CPointer::Struct_rb_iseq_struct] Branch target ISEQ
    :shape,      # @param [Symbol] Next0, Next1, or Default
    :target0,    # @param [RubyVM::RJIT::BranchTarget] First branch target
    :target1,    # @param [RubyVM::RJIT::BranchTarget,NilClass] Second branch target (optional)
    :compiler,   # @param [Symbol] The name of a callback to (re-)generate this branch stub
    :payload,    # @param [Object,NilClass] One optional argument to the :compiler callback
    :start_addr, # @param [Integer] Stub source start address to be re-generated
    :end_addr,   # @param [Integer] Stub source end address to be re-generated
  )
    def compile(asm)
      InsnCompiler.public_send(compiler, asm, self, *payload)
    end
  end

  class BranchTarget < Struct.new(
    :pc,      # @param [Integer]
    :c_ctx,   # @param [Integer]
    :address, # @param [Integer]
  )
    def initialize(pc:, ctx:, address: nil)
      super(pc:, c_ctx: ctx.save, address: address)
    end

    def ctx
      Context.load(c_ctx)
    end
  end
end
