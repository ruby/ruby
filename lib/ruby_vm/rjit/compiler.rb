require 'ruby_vm/rjit/assembler'
require 'ruby_vm/rjit/block'
require 'ruby_vm/rjit/branch_stub'
require 'ruby_vm/rjit/code_block'
require 'ruby_vm/rjit/context'
require 'ruby_vm/rjit/exit_compiler'
require 'ruby_vm/rjit/insn_compiler'
require 'ruby_vm/rjit/instruction'
require 'ruby_vm/rjit/invariants'
require 'ruby_vm/rjit/jit_state'

module RubyVM::RJIT
  # Compilation status
  KeepCompiling = :KeepCompiling
  CantCompile = :CantCompile
  EndBlock = :EndBlock

  # Ruby constants
  Qtrue = Fiddle::Qtrue
  Qfalse = Fiddle::Qfalse
  Qnil = Fiddle::Qnil
  Qundef = Fiddle::Qundef

  # Callee-saved registers
  # TODO: support using r12/r13 here
  EC  = :r14
  CFP = :r15
  SP  = :rbx

  # Scratch registers: rax, rcx

  # Mark objects in this Array during GC
  GC_REFS = []

  class Compiler
    attr_accessor :write_pos

    def self.decode_insn(encoded)
      INSNS.fetch(C.rb_vm_insn_decode(encoded))
    end

    # @param mem_size [Integer] JIT buffer size
    def initialize
      mem_size = C.rjit_opts.exec_mem_size * 1024 * 1024
      mem_block = C.mmap(mem_size)
      @cb = CodeBlock.new(mem_block: mem_block, mem_size: mem_size / 2)
      @ocb = CodeBlock.new(mem_block: mem_block + mem_size / 2, mem_size: mem_size / 2, outlined: true)
      @exit_compiler = ExitCompiler.new
      @insn_compiler = InsnCompiler.new(@cb, @ocb, @exit_compiler)
      Invariants.initialize(@cb, @ocb, self, @exit_compiler)
    end

    # Compile an ISEQ from its entry point.
    # @param iseq `RubyVM::RJIT::CPointer::Struct_rb_iseq_t`
    # @param cfp `RubyVM::RJIT::CPointer::Struct_rb_control_frame_t`
    def compile(iseq, cfp)
      # TODO: Support has_opt
      return if iseq.body.param.flags.has_opt

      jit = JITState.new(iseq:, cfp:)
      asm = Assembler.new
      asm.comment("Block: #{iseq.body.location.label}@#{C.rb_iseq_path(iseq)}:#{iseq.body.location.first_lineno}")
      compile_prologue(asm)
      compile_block(asm, jit:)
      iseq.body.jit_func = @cb.write(asm)
    rescue Exception => e
      $stderr.puts e.full_message
      exit 1
    end

    # Compile a branch stub.
    # @param branch_stub [RubyVM::RJIT::BranchStub]
    # @param cfp `RubyVM::RJIT::CPointer::Struct_rb_control_frame_t`
    # @param target0_p [TrueClass,FalseClass]
    # @return [Integer] The starting address of the compiled branch stub
    def branch_stub_hit(branch_stub, cfp, target0_p)
      # Update cfp->pc for `jit.at_current_insn?`
      target = target0_p ? branch_stub.target0 : branch_stub.target1
      cfp.pc = target.pc

      # Reuse an existing block if it already exists
      block = find_block(branch_stub.iseq, target.pc, target.ctx)

      # If the branch stub's jump is the last code, allow overwriting part of
      # the old branch code with the new block code.
      fallthrough = block.nil? && @cb.write_addr == branch_stub.end_addr
      if fallthrough
        # If the branch stub's jump is the last code, allow overwriting part of
        # the old branch code with the new block code.
        @cb.set_write_addr(branch_stub.start_addr)
        branch_stub.shape = target0_p ? Next0 : Next1
        Assembler.new.tap do |branch_asm|
          branch_stub.compile.call(branch_asm)
          @cb.write(branch_asm)
        end
      end

      # Reuse or generate a block
      if block
        target.address = block.start_addr
      else
        jit = JITState.new(iseq: branch_stub.iseq, cfp:)
        target.address = Assembler.new.then do |asm|
          compile_block(asm, jit:, pc: target.pc, ctx: target.ctx.dup)
          @cb.write(asm)
        end
        block = jit.block
      end
      block.incoming << branch_stub # prepare for invalidate_block

      # Re-generate the branch code for non-fallthrough cases
      unless fallthrough
        @cb.with_write_addr(branch_stub.start_addr) do
          branch_asm = Assembler.new
          branch_stub.compile.call(branch_asm)
          @cb.write(branch_asm)
        end
      end

      return target.address
    rescue Exception => e
      $stderr.puts e.full_message
      exit 1
    end

    # @param iseq `RubyVM::RJIT::CPointer::Struct_rb_iseq_t`
    # @param pc [Integer]
    def invalidate_blocks(iseq, pc)
      list_blocks(iseq, pc).each do |block|
        invalidate_block(block)
      end

      # If they were the ISEQ's first blocks, re-compile RJIT entry as well
      if iseq.body.iseq_encoded.to_i == pc
        iseq.body.jit_func = 0
        iseq.body.total_calls = 0
      end
    end

    def invalidate_block(block)
      iseq = block.iseq
      # Avoid touching GCed ISEQs. We assume it won't be re-entered.
      return unless C.imemo_type_p(iseq, C.imemo_iseq)

      # Remove this block from the version array
      remove_block(iseq, block)

      # Invalidate the block with entry exit
      unless block.invalidated
        @cb.with_write_addr(block.start_addr) do
          asm = Assembler.new
          asm.comment('invalidate_block')
          asm.jmp(block.entry_exit)
          @cb.write(asm)
        end
        block.invalidated = true
      end

      # Re-stub incoming branches
      block.incoming.each do |branch_stub|
        target = [branch_stub.target0, branch_stub.target1].compact.find do |target|
          target.pc == block.pc && target.ctx == block.ctx
        end
        next if target.nil?
        # TODO: Could target.address be a stub address? Is invalidation not needed in that case?

        # If the target being re-generated is currently a fallthrough block,
        # the fallthrough code must be rewritten with a jump to the stub.
        if target.address == branch_stub.end_addr
          branch_stub.shape = Default
        end

        target.address = Assembler.new.then do |ocb_asm|
          @exit_compiler.compile_branch_stub(block.ctx, ocb_asm, branch_stub, target == branch_stub.target0)
          @ocb.write(ocb_asm)
        end
        @cb.with_write_addr(branch_stub.start_addr) do
          branch_asm = Assembler.new
          branch_stub.compile.call(branch_asm)
          @cb.write(branch_asm)
        end
      end
    end

    private

    # Callee-saved: rbx, rsp, rbp, r12, r13, r14, r15
    # Caller-saved: rax, rdi, rsi, rdx, rcx, r8, r9, r10, r11
    #
    # @param asm [RubyVM::RJIT::Assembler]
    def compile_prologue(asm)
      asm.comment('RJIT entry point')

      # Save callee-saved registers used by JITed code
      asm.push(CFP)
      asm.push(EC)
      asm.push(SP)

      # Move arguments EC and CFP to dedicated registers
      asm.mov(EC, :rdi)
      asm.mov(CFP, :rsi)

      # Load sp to a dedicated register
      asm.mov(SP, [CFP, C.rb_control_frame_t.offsetof(:sp)]) # rbx = cfp->sp

      # Setup cfp->jit_return
      asm.mov(:rax, leave_exit)
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:jit_return)], :rax)
    end

    # @param asm [RubyVM::RJIT::Assembler]
    def compile_block(asm, jit:, pc: jit.iseq.body.iseq_encoded.to_i, ctx: Context.new)
      # Mark the block start address and prepare an exit code storage
      block = Block.new(iseq: jit.iseq, pc:, ctx: ctx.dup)
      jit.block = block
      asm.block(block)

      # Compile each insn
      iseq = jit.iseq
      index = (pc - iseq.body.iseq_encoded.to_i) / C.VALUE.size
      while index < iseq.body.iseq_size
        insn = self.class.decode_insn(iseq.body.iseq_encoded[index])
        jit.pc = (iseq.body.iseq_encoded + index).to_i

        # If previous instruction requested to record the boundary
        if jit.record_boundary_patch_point
          # Generate an exit to this instruction and record it
          exit_pos = Assembler.new.then do |ocb_asm|
            @exit_compiler.compile_side_exit(jit.pc, ctx, ocb_asm)
            @ocb.write(ocb_asm)
          end
          Invariants.record_global_inval_patch(asm, exit_pos)
          jit.record_boundary_patch_point = false
        end

        case status = @insn_compiler.compile(jit, ctx, asm, insn)
        when KeepCompiling
          # For now, reset the chain depth after each instruction as only the
          # first instruction in the block can concern itself with the depth.
          ctx.chain_depth = 0

          index += insn.len
        when EndBlock
          # TODO: pad nops if entry exit exists (not needed for x86_64?)
          break
        when CantCompile
          @exit_compiler.compile_side_exit(jit.pc, ctx, asm)

          # If this is the first instruction, this block never needs to be invalidated.
          if block.pc == iseq.body.iseq_encoded.to_i + index * C.VALUE.size
            block.invalidated = true
          end

          break
        else
          raise "compiling #{insn.name} returned unexpected status: #{status.inspect}"
        end
      end

      incr_counter(:compiled_block_count)
      set_block(iseq, block)
    end

    def leave_exit
      @leave_exit ||= Assembler.new.then do |asm|
        @exit_compiler.compile_leave_exit(asm)
        @ocb.write(asm)
      end
    end

    def incr_counter(name)
      if C.rjit_opts.stats
        C.rb_rjit_counters[name][0] += 1
      end
    end

    def list_blocks(iseq, pc)
      rjit_blocks(iseq)[pc].values
    end

    # @param [Integer] pc
    # @param [RubyVM::RJIT::Context] ctx
    # @return [RubyVM::RJIT::Block,NilClass]
    def find_block(iseq, pc, ctx)
      rjit_blocks(iseq)[pc][ctx]
    end

    # @param [RubyVM::RJIT::Block] block
    def set_block(iseq, block)
      rjit_blocks(iseq)[block.pc][block.ctx] = block
    end

    # @param [RubyVM::RJIT::Block] block
    def remove_block(iseq, block)
      rjit_blocks(iseq)[block.pc].delete(block.ctx)
    end

    def rjit_blocks(iseq)
      # Guard against ISEQ GC at random moments

      unless C.imemo_type_p(iseq, C.imemo_iseq)
        return Hash.new { |h, k| h[k] = {} }
      end

      unless iseq.body.rjit_blocks
        iseq.body.rjit_blocks = Hash.new { |h, k| h[k] = {} }
        # For some reason, rb_rjit_iseq_mark didn't protect this Hash
        # from being freed. So we rely on GC_REFS to keep the Hash.
        GC_REFS << iseq.body.rjit_blocks
      end
      iseq.body.rjit_blocks
    end
  end
end
