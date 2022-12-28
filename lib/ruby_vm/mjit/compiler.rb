require 'ruby_vm/mjit/context'
require 'ruby_vm/mjit/insn_compiler'
require 'ruby_vm/mjit/instruction'
require 'ruby_vm/mjit/jit_state'
require 'ruby_vm/mjit/x86_assembler'

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
      if C.mjit_opts.stats
        insn = decode_insn(C.VALUE.new(jit.pc).*)
        asm.comment("increment insn exit: #{insn.name}")
        asm.mov(:rax, (C.mjit_insn_exits + insn.bin).to_i)
        asm.add([:rax], 1) # TODO: lock
      end
      asm.comment("exit to interpreter")

      # Update pc
      asm.mov(:rax, jit.pc) # rax = jit.pc
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:pc)], :rax) # cfp->pc = rax

      # Update sp
      if ctx.stack_size > 0
        asm.add(SP, C.VALUE.size * ctx.stack_size) # rbx += stack_size
        asm.mov([CFP, C.rb_control_frame_t.offsetof(:sp)], SP) # cfp->sp = rbx
      end

      # Restore callee-saved registers
      asm.pop(SP)

      asm.mov(:rax, Qundef)
      asm.ret
    end

    def self.decode_insn(encoded)
      INSNS.fetch(C.rb_vm_insn_decode(encoded))
    end

    # @param mem_block [Integer] JIT buffer address
    def initialize(mem_block)
      @comments = Hash.new { |h, k| h[k] = [] }
      @mem_block = mem_block
      @write_pos = 0
      @insn_compiler = InsnCompiler.new
    end

    # @param iseq [RubyVM::MJIT::CPointer::Struct]
    def call(iseq)
      # TODO: Support has_opt
      return if iseq.body.param.flags.has_opt

      asm = X86Assembler.new
      asm.comment("Block: #{iseq.body.location.label}@#{pathobj_path(iseq.body.location.pathobj)}:#{iseq.body.location.first_lineno}")
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

      # Write machine code
      C.mjit_mark_writable
      @write_pos += asm.compile(start_addr)
      C.mjit_mark_executable

      end_addr = write_addr

      # Convert comment indexes to addresses
      asm.comments.each do |index, comments|
        @comments[start_addr + index] += comments
      end
      asm.comments.clear

      # Dump disasm if --mjit-dump-disasm
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
      asm.comment("MJIT entry")

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
        insn = self.class.decode_insn(iseq.body.iseq_encoded[index])
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
      asm.incr_counter(:mjit_insns_count)
      asm.comment("Insn: #{insn.name}")

      case insn.name
      when :putnil then @insn_compiler.putnil(jit, ctx, asm)
      when :leave  then @insn_compiler.leave(jit, ctx, asm)
      # throw
      # jump
      # branchif
      # branchunless
      # branchnil
      # once
      # opt_case_dispatch
      # opt_plus
      # opt_minus
      # opt_mult
      # opt_div
      # opt_mod
      # opt_eq
      # opt_neq
      # opt_lt
      # opt_le
      # opt_gt
      # opt_ge
      # opt_ltlt
      # opt_and
      # opt_or
      # opt_aref
      # opt_aset
      # opt_aset_with
      # opt_aref_with
      # opt_length
      # opt_size
      # opt_empty_p
      # opt_succ
      # opt_not
      # opt_regexpmatch2
      # invokebuiltin
      # opt_invokebuiltin_delegate
      # opt_invokebuiltin_delegate_leave
      when :getlocal_WC_0 then @insn_compiler.getlocal_WC_0(jit, ctx, asm)
      else CantCompile
      end
    end

    def dump_disasm(from, to)
      C.dump_disasm(from, to).each do |address, mnemonic, op_str|
        @comments.fetch(address, []).each do |comment|
          puts bold("  # #{comment}")
        end
        puts "  0x#{format("%x", address)}: #{mnemonic} #{op_str}"
      end
      puts
    end

    def bold(text)
      "\e[1m#{text}\e[0m"
    end

    # vm_core.h: pathobj_path
    def pathobj_path(pathobj)
      if pathobj.is_a?(String)
        pathobj
      else
        pathobj.first
      end
    end
  end
end
