require 'test/unit'
require_relative '../../lib/jit_support'

return unless JITSupport.rjit_supported?
return unless RubyVM::RJIT.enabled?
return unless RubyVM::RJIT::C.HAVE_LIBCAPSTONE

require 'stringio'
require 'ruby_vm/rjit/assembler'

module RubyVM::RJIT
  class TestAssembler < Test::Unit::TestCase
    MEM_SIZE = 16 * 1024

    def setup
      @mem_block ||= C.mmap(MEM_SIZE)
      @cb = CodeBlock.new(mem_block: @mem_block, mem_size: MEM_SIZE)
    end

    def test_add
      asm = Assembler.new
      asm.add(:rax, 255)
      assert_compile(asm, '0x0: add rax, 0xff')
    end

    def test_jmp
      asm = Assembler.new
      label = asm.new_label('label')
      asm.jmp(label)
      asm.write_label(label)
      asm.jmp(label)
      assert_compile(asm, <<~EOS)
        0x0: jmp 0x2
        0x2: jmp 0x2
      EOS
    end

    private

    def assert_compile(asm, expected)
      actual = compile(asm)
      assert_equal expected, actual, "---\n#{actual}---"
    end

    def compile(asm)
      start_addr = @cb.write_addr
      @cb.write(asm)
      end_addr = @cb.write_addr

      io = StringIO.new
      @cb.dump_disasm(start_addr, end_addr, io:, color: false)
      io.seek(0)
      disasm = io.read

      disasm.gsub!(/^  /, '')
      disasm.sub!(/\n\z/, '')
      if disasm.lines.size == 1
        disasm.rstrip!
      end
      (start_addr...end_addr).each do |addr|
        disasm.gsub!("0x#{addr.to_s(16)}", "0x#{(addr - start_addr).to_s(16)}")
      end
      disasm
    end
  end
end
