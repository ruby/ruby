require 'set'

module RubyVM::MJIT
  class Invariants
    class << self
      # Called by RubyVM::MJIT::Compiler to lazily initialize this
      # @param cb [CodeBlock]
      # @param ocb [CodeBlock]
      # @param exit_compiler [RubyVM::MJIT::ExitCompiler]
      def initialize(cb, ocb, exit_compiler)
        @cb = cb
        @ocb = ocb
        @exit_compiler = exit_compiler
        @bop_blocks = Set.new # TODO: actually invalidate this
        @cme_blocks = Hash.new { |h, k| h[k] = Set.new }
        @patches = {}

        # freeze # workaround a binding.irb issue. TODO: resurrect this
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

      # @param asm [RubyVM::MJIT::Assembler]
      def record_global_inval_patch(asm, target)
        asm.pos_marker do |address|
          if @patches.key?(address)
            raise 'multiple patches in the same address'
          end
          @patches[address] = target
        end
      end

      def on_cme_invalidate(cme)
        @cme_blocks.fetch(cme.to_i, []).each do |block|
          @cb.with_write_addr(block.start_addr) do
            asm = Assembler.new
            asm.comment('on_cme_invalidate')
            asm.jmp(block.entry_exit)
            @cb.write(asm)
          end
          # TODO: re-generate branches that refer to this block
        end
      end

      def on_tracing_invalidate_all
        # On-Stack Replacement
        @patches.each do |address, target|
          # TODO: assert patches don't overlap each other
          @cb.with_write_addr(address) do
            asm = Assembler.new
            asm.comment('on_tracing_invalidate_all')
            asm.jmp(target)
            @cb.write(asm)
          end
        end

        # Avoid reusing past code
        Compiler.reset_blocks

        C.mjit_for_each_iseq do |iseq|
          # Disable entering past code
          iseq.body.jit_func = 0
          # Compile this again if not converted to trace_* insns
          iseq.body.total_calls = 0
        end
      end

      private

      # @param block [RubyVM::MJIT::Block]
      def ensure_block_entry_exit(block, cause:)
        if block.entry_exit.nil?
          block.entry_exit = Assembler.new.then do |asm|
            @exit_compiler.compile_entry_exit(block.pc, block.ctx, asm, cause:)
            @ocb.write(asm)
          end
        end
      end
    end
  end
end
