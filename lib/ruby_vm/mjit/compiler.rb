require 'mjit/insn_compiler'
require 'mjit/instruction'
require 'mjit/x86_assembler'

module RubyVM::MJIT
  # Compilation status
  KeepCompiling = :KeepCompiling
  CantCompile = :CantCompile
  EndBlock = :EndBlock

  # Ruby constants
  Qnil = Fiddle::Qnil
  Qundef = Fiddle::Qundef

  class Compiler
    attr_accessor :write_pos

    # @param mem_block [Integer] JIT buffer address
    def initialize(mem_block)
      @mem_block = mem_block
      @write_pos = 0
      @insn_compiler = InsnCompiler.new
    end

    # @param iseq [RubyVM::MJIT::CPointer::Struct]
    def call(iseq)
      return if iseq.body.location.label == '<main>'

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
    def compile_prologue(asm)
      asm.mov(:rbx, [:rsi, C.rb_control_frame_t.offsetof(:sp)]) # rbx = cfp->sp
    end

    def compile_block(asm, iseq)
      index = 0
      while index < iseq.body.iseq_size
        insn = decode_insn(iseq.body.iseq_encoded[index])
        case compile_insn(asm, insn)
        when EndBlock
          break
        when CantCompile
          compile_exit(asm, (iseq.body.iseq_encoded + index).to_i)
          break
        end
        index += insn.len
      end
    end

    def compile_insn(asm, insn)
      case insn.name
      when :putnil then @insn_compiler.putnil(asm)
      #when :leave  then @insn_compiler.leave(asm)
      else CantCompile
      end
    end

    def compile_exit(asm, exit_pc)
      # update pc
      asm.mov(:rax, exit_pc) # rax = exit_pc
      asm.mov([:rsi, C.rb_control_frame_t.offsetof(:pc)], :rax) # cfp->pc = rax

      # update sp (TODO: consider JIT state)
      asm.add(:rbx, C.VALUE.size) # rbx += 1
      asm.mov([:rsi, C.rb_control_frame_t.offsetof(:sp)], :rbx) # cfp->sp = rbx

      asm.mov(:rax, Qundef)
      asm.ret
    end

    def decode_insn(encoded)
      INSNS.fetch(C.rb_vm_insn_decode(encoded))
    end

    def dump_disasm(from, to)
      C.dump_disasm(from, to).each do |address, mnemonic, op_str|
        puts "  0x#{"%p" % address}: #{mnemonic} #{op_str}"
      end
    end
  end
end
