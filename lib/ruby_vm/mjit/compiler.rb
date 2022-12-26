require 'mjit/context'
require 'mjit/insn_compiler'
require 'mjit/instruction'
require 'mjit/jit_state'
require 'mjit/x86_assembler'

module RubyVM::MJIT
  # Compilation status
  KeepCompiling = :KeepCompiling
  CantCompile = :CantCompile
  EndBlock = :EndBlock

  # Ruby constants
  Qnil = Fiddle::Qnil
  Qundef = Fiddle::Qundef

  # Fixed registers
  EC  = :rdi # TODO: change this
  CFP = :rsi # TODO: change this
  SP  = :rbx

  class Compiler
    attr_accessor :write_pos

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::X86Assembler]
    def self.compile_exit(jit, ctx, asm)
      # update pc
      asm.mov(:rax, jit.pc) # rax = jit.pc
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:pc)], :rax) # cfp->pc = rax

      # update sp
      if ctx.stack_size > 0
        asm.add(SP, C.VALUE.size * ctx.stack_size) # rbx += stack_size
        asm.mov([CFP, C.rb_control_frame_t.offsetof(:sp)], SP) # cfp->sp = rbx
      end

      # Restore callee-saved registers
      asm.pop(SP)

      asm.mov(:rax, Qundef)
      asm.ret
    end

    # @param mem_block [Integer] JIT buffer address
    def initialize(mem_block)
      @mem_block = mem_block
      @write_pos = 0
      @insn_compiler = InsnCompiler.new
    end

    # @param iseq [RubyVM::MJIT::CPointer::Struct]
    def call(iseq)
      # TODO: Support has_opt
      return if iseq.body.param.flags.has_opt

      asm = X86Assembler.new
      compile_prologue(asm)
      compile_block(asm, iseq)
      iseq.body.jit_func = compile(asm)
    rescue Exception => e
      $stderr.puts e.full_message # TODO: check verbose
    end

    def write_addr
      @mem_block + @write_pos
    end

    private

    # @param asm [RubyVM::MJIT::X86Assembler]
    def compile(asm)
      start_addr = write_addr

      C.mjit_mark_writable
      @write_pos += asm.compile(start_addr)
      C.mjit_mark_executable

      end_addr = write_addr
      if C.mjit_opts.dump_disasm && start_addr < end_addr
        dump_disasm(start_addr, end_addr)
      end
      start_addr
    end

    #  ec: rdi
    # cfp: rsi
    #
    # Callee-saved: rbx, rsp, rbp, r12, r13, r14, r15
    # Caller-saved: rax, rdi, rsi, rdx, rcx, r8, r9, r10, r11
    #
    # @param asm [RubyVM::MJIT::X86Assembler]
    def compile_prologue(asm)
      # Save callee-saved registers used by JITed code
      asm.push(SP)

      # Load sp to a register
      asm.mov(SP, [CFP, C.rb_control_frame_t.offsetof(:sp)]) # rbx = cfp->sp
    end

    # @param asm [RubyVM::MJIT::X86Assembler]
    def compile_block(asm, iseq)
      jit = JITState.new
      ctx = Context.new

      index = 0
      while index < iseq.body.iseq_size
        insn = decode_insn(iseq.body.iseq_encoded[index])
        jit.pc = (iseq.body.iseq_encoded + index).to_i

        case compile_insn(jit, ctx, asm, insn)
        when EndBlock
          break
        when CantCompile
          self.class.compile_exit(jit, ctx, asm)
          break
        end
        index += insn.len
      end
    end

    # @param jit [RubyVM::MJIT::JITState]
    # @param ctx [RubyVM::MJIT::Context]
    # @param asm [RubyVM::MJIT::X86Assembler]
    def compile_insn(jit, ctx, asm, insn)
      case insn.name
      when :putnil then @insn_compiler.putnil(jit, ctx, asm)
      when :leave  then @insn_compiler.leave(jit, ctx, asm)
      else CantCompile
      end
    end

    def decode_insn(encoded)
      INSNS.fetch(C.rb_vm_insn_decode(encoded))
    end

    def dump_disasm(from, to)
      C.dump_disasm(from, to).each do |address, mnemonic, op_str|
        puts "  0x#{"%x" % address}: #{mnemonic} #{op_str}"
      end
      puts
    end
  end
end
