require 'ruby_vm/mjit/assembler'
require 'ruby_vm/mjit/block'
require 'ruby_vm/mjit/block_stub'
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

    # Continue compilation from a stub.
    # @param stub [RubyVM::MJIT::BlockStub]
    # @param cfp `RubyVM::MJIT::CPointer::Struct_rb_control_frame_t`
    # @return [Integer] The starting address of a compiled stub
    def stub_hit(stub, cfp)
      # Update cfp->pc for `jit.at_current_insn?`
      cfp.pc = stub.pc

      # Prepare the jump target
      new_asm = Assembler.new.tap do |asm|
        jit = JITState.new(iseq: stub.iseq, cfp:)
        compile_block(asm, jit:, pc: stub.pc, ctx: stub.ctx)
      end

      # Rewrite the stub
      if @cb.write_addr == stub.end_addr
        # If the stub jump is the last code, overwrite the jump with the new code.
        @cb.set_write_addr(stub.start_addr)
        @cb.write(new_asm)
      else
        # If the stub jump is old code, change the jump target to the new code.
        new_addr = @cb.write(new_asm)
        @cb.with_write_addr(stub.start_addr) do
          asm = Assembler.new
          asm.comment('regenerate block stub')
          asm.jmp(new_addr)
          @cb.write(asm)
        end
      end
    end

    private

    # Callee-saved: rbx, rsp, rbp, r12, r13, r14, r15
    # Caller-saved: rax, rdi, rsi, rdx, rcx, r8, r9, r10, r11
    #
    # @param asm [RubyVM::MJIT::Assembler]
    def compile_prologue(asm)
      asm.comment('MJIT entry')

      # Save callee-saved registers used by JITed code
      asm.push(CFP)
      asm.push(EC)
      asm.push(SP)

      # Move arguments EC and CFP to dedicated registers
      asm.mov(EC, :rdi)
      asm.mov(CFP, :rsi)

      # Load sp to a dedicated register
      asm.mov(SP, [CFP, C.rb_control_frame_t.offsetof(:sp)]) # rbx = cfp->sp
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

        case @insn_compiler.compile(jit, ctx, asm, insn)
        when EndBlock
          # TODO: pad nops if entry exit exists
          break
        when CantCompile
          @exit_compiler.compile_side_exit(jit, ctx, asm)
          break
        end
        index += insn.len
      end
    end
  end
end
