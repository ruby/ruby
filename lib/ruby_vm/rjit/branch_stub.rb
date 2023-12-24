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
      BranchTarget.new(c_target0)
    end

    def target0=(target)
      self.c_target0 = target.to_i
    end

    def target1
      BranchTarget.new(c_target1)
    end

    def target1=(target)
      self.c_target1 = target.to_i
    end
  end

  # @param pc [Integer]
  # @param ctx [Context]
  # @param address [Integer]
  class BranchTarget
    def initialize(addr = nil, pc: nil, ctx: nil, address: nil)
      @branch_target = C.rb_rjit_branch_target.new(addr)
      if addr.nil?
        self.pc = pc
        @branch_target.ctx = ctx.to_c
        self.address = address
      end
    end

    # Attribute readers and writers
    def pc = @branch_target.pc
    def pc=(pc); @branch_target.pc = pc; end
    def ctx = Context.new(@branch_target.ctx.to_i)
    def address = @branch_target.address
    def address=(address); @branch_target.address = address; end

    def ==(other)
      self.to_a == other.to_a
    end

    def hash
      to_a.hash
    end

    def to_a
      [
        self.pc,
        self.ctx,
        self.address,
      ]
    end

    def to_i # TODO: remove later?
      @branch_target.to_i
    end
  end
end
