require 'set'

module RubyVM::MJIT
  class Invariants
    # @param ocb [CodeBlock]
    # @param exit_compiler [RubyVM::MJIT::ExitCompiler]
    def initialize(ocb, exit_compiler)
      @ocb = ocb
      @exit_compiler = exit_compiler
      @bop_blocks = Set.new # TODO: actually invalidate this
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param klass [Integer]
    # @param op [Integer]
    def assume_bop_not_redefined(jit, klass, op)
      return false unless C.BASIC_OP_UNREDEFINED_P(klass, op)

      ensure_block_entry_exit(jit.block, cause: 'assume_bop_not_redefined')
      @bop_blocks << jit.block
      true
    end

    private

    # @param block [RubyVM::MJIT::Block]
    def ensure_block_entry_exit(block, cause:)
      if block.entry_exit.nil?
        asm = Assembler.new
        @exit_compiler.compile_entry_exit(block.pc, asm, cause:)
        block.entry_exit = @ocb.write(asm)
      end
    end
  end
end
