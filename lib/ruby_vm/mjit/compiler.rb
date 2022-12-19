require 'mjit/insn_compiler'
require 'mjit/instruction'
require 'mjit/x86_assembler'

module RubyVM::MJIT
  # Compilation status
  KeepCompiling = :keep_compiling
  CantCompile = :cant_compile
  EndBlock = :end_block

  class Compiler
    # Ruby constants
    Qundef = Fiddle::Qundef

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
      iseq.body.jit_func = compile_block(iseq)
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

    # ec -> RDI, cfp -> RSI
    def compile_block(iseq)
      addr = write_addr
      asm = X86Assembler.new

      index = 0
      while index < iseq.body.iseq_size
        insn = decode_insn(iseq.body.iseq_encoded[index])
        status = compile_insn(asm, insn)
        if status == EndBlock
          break
        end
        index += insn.len
      end

      compile(asm)
    end

    def compile_insn(asm, insn)
      case insn.name
      when :putnil then @insn_compiler.putnil(asm)
      when :leave  then @insn_compiler.leave(asm)
      else raise NotImplementedError, "insn '#{insn.name}' is not supported yet"
      end
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
