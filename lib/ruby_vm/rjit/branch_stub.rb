module RubyVM::RJIT
  # Branch shapes
  Next0   = :Next0   # target0 is a fallthrough
  Next1   = :Next1   # target1 is a fallthrough
  Default = :Default # neither targets is a fallthrough

  class BranchStub < Struct.new(
    :iseq,       # @param [RubyVM::RJIT::CPointer::Struct_rb_iseq_struct] Branch target ISEQ
    :shape,      # @param [Symbol] Next0, Next1, or Default
    :c_target0,  # @param [Integer] First branch target
    :c_target1,  # @param [Integer,NilClass] Second branch target (optional)
    :compiler,   # @param [Symbol] The name of a callback to (re-)generate this branch stub
    :payload,    # @param [Object,NilClass] One optional argument to the :compiler callback
    :start_addr, # @param [Integer] Stub source start address to be re-generated
    :end_addr,   # @param [Integer] Stub source end address to be re-generated
  )
    def compile(asm)
      InsnCompiler.public_send(compiler, asm, self, *payload)
    end

    def target0
      BranchTarget.load(c_target0)
    end

    def target0=(target)
      self.c_target0 = target.save
    end

    def target1
      BranchTarget.load(c_target1)
    end

    def target1=(target)
      self.c_target1 = target.save
    end
  end

  class BranchTarget < Struct.new(
    :pc,      # @param [Integer]
    :ctx,     # @param [Context]
    :address, # @param [Integer]
  )
    def save
      c_target = C.rb_rjit_branch_target.new
      c_target.pc = pc
      c_target.ctx = ctx.to_c
      c_target.address = address
      c_target.to_i
    end

    def self.load(c_target_addr)
      c_target = C.rb_rjit_branch_target.new(c_target_addr)
      target = BranchTarget.new
      target.pc = c_target.pc
      target.ctx = Context.new(c_target.ctx.to_i)
      target.address = c_target.address
      target.freeze
    end
  end
end
