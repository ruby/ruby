require 'ruby_vm/mjit/assembler'
require 'ruby_vm/mjit/block'
require 'ruby_vm/mjit/branch_stub'
require 'ruby_vm/mjit/code_block'
require 'ruby_vm/mjit/context'
require 'ruby_vm/mjit/exit_compiler'
require 'ruby_vm/mjit/insn_compiler'
require 'ruby_vm/mjit/instruction'
require 'ruby_vm/mjit/invariants'
require 'ruby_vm/mjit/jit_state'

module RubyVM::MJIT
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

  class Compiler
    attr_accessor :write_pos

    IseqBlocks = Hash.new { |h, k| h[k] = {} }

    def self.decode_insn(encoded)
      INSNS.fetch(C.rb_vm_insn_decode(encoded))
    end

    # @param mem_block [Integer] JIT buffer address
    # @param mem_size  [Integer] JIT buffer size
    def initialize(mem_block, mem_size)
      @cb = CodeBlock.new(mem_block: mem_block, mem_size: mem_size / 2)
      @ocb = CodeBlock.new(mem_block: mem_block + mem_size / 2, mem_size: mem_size / 2, outlined: true)
      @exit_compiler = ExitCompiler.new
      @insn_compiler = InsnCompiler.new(@cb, @ocb, @exit_compiler)

      @leave_exit = Assembler.new.then do |asm|
        @exit_compiler.compile_leave_exit(asm)
        @ocb.write(asm)
      end
    end

    # Compile an ISEQ from its entry point.
    # @param iseq `RubyVM::MJIT::CPointer::Struct_rb_iseq_t`
    # @param cfp `RubyVM::MJIT::CPointer::Struct_rb_control_frame_t`
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
      $stderr.puts e.full_message # TODO: check verbose
    end

    # Compile a branch stub.
    # @param branch_stub [RubyVM::MJIT::BranchStub]
    # @param cfp `RubyVM::MJIT::CPointer::Struct_rb_control_frame_t`
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
        set_block(branch_stub.iseq, target.pc, target.ctx, jit.block)
      end

      # Re-generate the branch code for non-fallthrough cases
      unless fallthrough
        @cb.with_write_addr(branch_stub.start_addr) do
          branch_asm = Assembler.new
          branch_stub.compile.call(branch_asm)
          @cb.write(branch_asm)
        end
      end

      return target.address
    end

    private

    # Callee-saved: rbx, rsp, rbp, r12, r13, r14, r15
    # Caller-saved: rax, rdi, rsi, rdx, rcx, r8, r9, r10, r11
    #
    # @param asm [RubyVM::MJIT::Assembler]
    def compile_prologue(asm)
      asm.comment('MJIT entry point')

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
      asm.mov(:rax, @leave_exit)
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:jit_return)], :rax)
    end

    # @param asm [RubyVM::MJIT::Assembler]
    def compile_block(asm, jit:, pc: jit.iseq.body.iseq_encoded.to_i, ctx: Context.new)
      # Mark the block start address and prepare an exit code storage
      jit.block = Block.new(pc:)
      asm.block(jit.block)

      # Compile each insn
      iseq = jit.iseq
      index = (pc - iseq.body.iseq_encoded.to_i) / C.VALUE.size
      while index < iseq.body.iseq_size
        insn = self.class.decode_insn(iseq.body.iseq_encoded[index])
        jit.pc = (iseq.body.iseq_encoded + index).to_i

        case status = @insn_compiler.compile(jit, ctx, asm, insn)
        when KeepCompiling
          index += insn.len
        when EndBlock
          # TODO: pad nops if entry exit exists
          break
        when CantCompile
          @exit_compiler.compile_side_exit(jit, ctx, asm)
          break
        else
          raise "compiling #{insn.name} returned unexpected status: #{status.inspect}"
        end
      end

      incr_counter(:compiled_block_count)
    end

    def incr_counter(name)
      if C.mjit_opts.stats
        C.rb_mjit_counters[name][0] += 1
      end
    end

    def mjit_blocks(iseq)
      iseq.body.mjit_blocks ||= {}
    end

    # @param [Integer] pc
    # @param [RubyVM::MJIT::Context] ctx
    # @return [RubyVM::MJIT::Block,NilClass]
    def find_block(iseq, pc, ctx)
      IseqBlocks[iseq.to_i][[pc, ctx]]
    end

    # @param [Integer] pc
    # @param [RubyVM::MJIT::Context] ctx
    # @param [RubyVM::MJIT::Block] block
    def set_block(iseq, pc, ctx, block)
      IseqBlocks[iseq.to_i][[pc, ctx]] = block
    end
  end
end
