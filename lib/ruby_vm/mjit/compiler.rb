require 'ruby_vm/mjit/assembler'
require 'ruby_vm/mjit/block'
require 'ruby_vm/mjit/block_stub'
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

    def self.decode_insn(encoded)
      INSNS.fetch(C.rb_vm_insn_decode(encoded))
    end

    # @param mem_block [Integer] JIT buffer address
    # @param mem_size  [Integer] JIT buffer size
    def initialize(mem_block, mem_size)
      @cb = CodeBlock.new(mem_block: mem_block, mem_size: mem_size / 2)
      @ocb = CodeBlock.new(mem_block: mem_block + mem_size / 2, mem_size: mem_size / 2, outlined: true)
      @exit_compiler = ExitCompiler.new
      @insn_compiler = InsnCompiler.new(@ocb, @exit_compiler)

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

      asm = Assembler.new
      asm.comment("Block: #{iseq.body.location.label}@#{C.rb_iseq_path(iseq)}:#{iseq.body.location.first_lineno}")
      compile_prologue(asm)
      compile_block(asm, jit: JITState.new(iseq:, cfp:))
      iseq.body.jit_func = @cb.write(asm)
    rescue Exception => e
      $stderr.puts e.full_message # TODO: check verbose
    end

    # Continue compilation from a block stub.
    # @param block_stub [RubyVM::MJIT::BlockStub]
    # @param cfp `RubyVM::MJIT::CPointer::Struct_rb_control_frame_t`
    # @return [Integer] The starting address of the compiled block stub
    def block_stub_hit(block_stub, cfp)
      # Update cfp->pc for `jit.at_current_insn?`
      cfp.pc = block_stub.pc

      # Prepare the jump target
      new_asm = Assembler.new.tap do |asm|
        jit = JITState.new(iseq: block_stub.iseq, cfp:)
        compile_block(asm, jit:, pc: block_stub.pc, ctx: block_stub.ctx)
      end

      # Rewrite the block stub
      if @cb.write_addr == block_stub.end_addr
        # If the block stub's jump is the last code, overwrite the jump with the new code.
        @cb.set_write_addr(block_stub.start_addr)
        @cb.write(new_asm)
      else
        # If the block stub's jump is old code, change the jump target to the new code.
        new_addr = @cb.write(new_asm)
        @cb.with_write_addr(block_stub.start_addr) do
          asm = Assembler.new
          block_stub.change_block.call(asm, new_addr)
          @cb.write(asm)
        end
        new_addr
      end
    end

    # Compile a branch stub.
    # @param branch_stub [RubyVM::MJIT::BranchStub]
    # @param cfp `RubyVM::MJIT::CPointer::Struct_rb_control_frame_t`
    # @param branch_target_p [TrueClass,FalseClass]
    # @return [Integer] The starting address of the compiled branch stub
    def branch_stub_hit(branch_stub, cfp, branch_target_p)
      # Update cfp->pc for `jit.at_current_insn?`
      pc = branch_target_p ? branch_stub.branch_target_pc : branch_stub.fallthrough_pc
      cfp.pc = pc

      # Prepare the jump target
      new_asm = Assembler.new.tap do |asm|
        jit = JITState.new(iseq: branch_stub.iseq, cfp:)
        compile_block(asm, jit:, pc:, ctx: branch_stub.ctx.dup)
      end

      # Rewrite the branch stub
      if @cb.write_addr == branch_stub.end_addr
        # If the branch stub's jump is the last code, overwrite the jump with the new code.
        @cb.set_write_addr(branch_stub.start_addr)
        Assembler.new.tap do |branch_asm|
          if branch_target_p
            branch_stub.branch_target_next.call(branch_asm)
          else
            branch_stub.fallthrough_next.call(branch_asm)
          end
          @cb.write(branch_asm)
        end

        # Compile a fallthrough over the jump
        if branch_target_p
          branch_stub.branch_target_addr = @cb.write(new_asm)
        else
          branch_stub.fallthrough_addr = @cb.write(new_asm)
        end
      else
        # Otherwise, just prepare the new code somewhere
        if branch_target_p
          unless @cb.include?(branch_stub.branch_target_addr)
            branch_stub.branch_target_addr = @cb.write(new_asm)
          end
        else
          unless @cb.include?(branch_stub.fallthrough_addr)
            branch_stub.fallthrough_addr = @cb.write(new_asm)
          end
        end

        # Update jump destinations
        branch_asm = Assembler.new
        if branch_stub.end_addr == branch_stub.branch_target_addr # branch_target_next has been used
          branch_stub.branch_target_next.call(branch_asm)
        elsif branch_stub.end_addr == branch_stub.fallthrough_addr # fallthrough_next has been used
          branch_stub.fallthrough_next.call(branch_asm)
        else
          branch_stub.neither_next.call(branch_asm)
        end
        @cb.with_write_addr(branch_stub.start_addr) do
          @cb.write(branch_asm)
        end
      end

      if branch_target_p
        branch_stub.branch_target_addr
      else
        branch_stub.fallthrough_addr
      end
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
    end
  end
end
