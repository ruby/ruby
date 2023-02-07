require 'set'

module RubyVM::MJIT
  class Invariants
    # @param cb [CodeBlock]
    # @param ocb [CodeBlock]
    # @param exit_compiler [RubyVM::MJIT::ExitCompiler]
    def initialize(cb, ocb, exit_compiler)
      @cb = cb
      @ocb = ocb
      @exit_compiler = exit_compiler
      @bop_blocks = Set.new # TODO: actually invalidate this
      @cme_blocks = Hash.new { |h, k| h[k] = Set.new }

      invariants = self
      hooks = Module.new
      hooks.define_method(:on_cme_invalidate) do |cme|
        invariants.on_cme_invalidate(cme)
      end
      Hooks.singleton_class.prepend(hooks)
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

    # @param jit [RubyVM::MJIT::JITState]
    def assume_method_lookup_stable(jit, cme)
      ensure_block_entry_exit(jit.block, cause: 'assume_method_lookup_stable')
      @cme_blocks[cme.to_i] << jit.block
    end

    def on_cme_invalidate(cme)
      @cme_blocks.fetch(cme.to_i, []).each do |block|
        @cb.with_write_addr(block.start_addr) do
          asm = Assembler.new
          asm.jmp(block.entry_exit)
          @cb.write(asm)
        end
        # TODO: re-generate branches that refer to this block
      end
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
