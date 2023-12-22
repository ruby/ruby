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
      asm.add([:rcx], 1)        # ADD r/m64, imm8 (Mod 00: [reg])
      asm.add(:rax, 0x7f)       # ADD r/m64, imm8 (Mod 11: reg)
      asm.add(:rbx, 0x7fffffff) # ADD r/m64 imm32 (Mod 11: reg)
      asm.add(:rsi, :rdi)       # ADD r/m64, r64 (Mod 11: reg)
      assert_compile(asm, <<~EOS)
        0x0: add qword ptr [rcx], 1
        0x4: add rax, 0x7f
        0x8: add rbx, 0x7fffffff
        0xf: add rsi, rdi
      EOS
    end

    def test_and
      asm = Assembler.new
      asm.and(:rax, 0)          # AND r/m64, imm8 (Mod 11: reg)
      asm.and(:rbx, 0x7fffffff) # AND r/m64, imm32 (Mod 11: reg)
      asm.and(:rcx, [:rdi, 8])  # AND r64, r/m64 (Mod 01: [reg]+disp8)
      assert_compile(asm, <<~EOS)
        0x0: and rax, 0
        0x4: and rbx, 0x7fffffff
        0xb: and rcx, qword ptr [rdi + 8]
      EOS
    end

    def test_call
      asm = Assembler.new
      asm.call(rel32(0xff)) # CALL rel32
      asm.call(:rax)        # CALL r/m64 (Mod 11: reg)
      assert_compile(asm, <<~EOS)
        0x0: call 0xff
        0x5: call rax
      EOS
    end

    def test_cmove
      asm = Assembler.new
      asm.cmove(:rax, :rcx) # CMOVE r64, r/m64 (Mod 11: reg)
      assert_compile(asm, <<~EOS)
        0x0: cmove rax, rcx
      EOS
    end

    def test_cmovg
      asm = Assembler.new
      asm.cmovg(:rbx, :rdi) # CMOVG r64, r/m64 (Mod 11: reg)
      assert_compile(asm, <<~EOS)
        0x0: cmovg rbx, rdi
      EOS
    end

    def test_cmovge
      asm = Assembler.new
      asm.cmovge(:rsp, :rbp) # CMOVGE r64, r/m64 (Mod 11: reg)
      assert_compile(asm, <<~EOS)
        0x0: cmovge rsp, rbp
      EOS
    end

    def test_cmovl
      asm = Assembler.new
      asm.cmovl(:rdx, :rsp) # CMOVL r64, r/m64 (Mod 11: reg)
      assert_compile(asm, <<~EOS)
        0x0: cmovl rdx, rsp
      EOS
    end

    def test_cmovle
      asm = Assembler.new
      asm.cmovle(:rax, :rax) # CMOVLE r64, r/m64 (Mod 11: reg)
      assert_compile(asm, <<~EOS)
        0x0: cmovle rax, rax
      EOS
    end

    def test_cmovne
      asm = Assembler.new
      asm.cmovne(:rax, :rbx) # CMOVNE r64, r/m64 (Mod 11: reg)
      assert_compile(asm, <<~EOS) # cmovne == cmovnz
        0x0: cmovne rax, rbx
      EOS
    end

    def test_cmovnz
      asm = Assembler.new
      asm.cmovnz(:rax, :rbx) # CMOVNZ r64, r/m64 (Mod 11: reg)
      assert_compile(asm, <<~EOS) # cmovne == cmovnz
        0x0: cmovne rax, rbx
      EOS
    end

    def test_cmovz
      asm = Assembler.new
      asm.cmovz(:rax, :rbx) # CMOVZ r64, r/m64 (Mod 11: reg)
      assert_compile(asm, <<~EOS) # cmove == cmovz
        0x0: cmove rax, rbx
      EOS
    end

    def test_cmp
      asm = Assembler.new
      asm.cmp(BytePtr[:rax, 8], 8)      # CMP r/m8, imm8 (Mod 01: [reg]+disp8)
      asm.cmp(DwordPtr[:rax, 8], 0x100) # CMP r/m32, imm32 (Mod 01: [reg]+disp8)
      asm.cmp([:rax, 8], 8)             # CMP r/m64, imm8 (Mod 01: [reg]+disp8)
      asm.cmp([:rbx, 8], 0x100)         # CMP r/m64, imm32 (Mod 01: [reg]+disp8)
      asm.cmp([:rax, 0x100], 8)         # CMP r/m64, imm8 (Mod 10: [reg]+disp32)
      asm.cmp(:rax, 8)                  # CMP r/m64, imm8 (Mod 11: reg)
      asm.cmp(:rax, 0x100)              # CMP r/m64, imm32 (Mod 11: reg)
      asm.cmp([:rax, 8], :rbx)          # CMP r/m64, r64 (Mod 01: [reg]+disp8)
      asm.cmp([:rax, -0x100], :rbx)     # CMP r/m64, r64 (Mod 10: [reg]+disp32)
      asm.cmp(:rax, :rbx)               # CMP r/m64, r64 (Mod 11: reg)
      assert_compile(asm, <<~EOS)
        0x0: cmp byte ptr [rax + 8], 8
        0x4: cmp dword ptr [rax + 8], 0x100
        0xb: cmp qword ptr [rax + 8], 8
        0x10: cmp qword ptr [rbx + 8], 0x100
        0x18: cmp qword ptr [rax + 0x100], 8
        0x20: cmp rax, 8
        0x24: cmp rax, 0x100
        0x2b: cmp qword ptr [rax + 8], rbx
        0x2f: cmp qword ptr [rax - 0x100], rbx
        0x36: cmp rax, rbx
      EOS
    end

    def test_jbe
      asm = Assembler.new
      asm.jbe(rel32(0xff)) # JBE rel32
      assert_compile(asm, <<~EOS)
        0x0: jbe 0xff
      EOS
    end

    def test_je
      asm = Assembler.new
      asm.je(rel32(0xff)) # JE rel32
      assert_compile(asm, <<~EOS)
        0x0: je 0xff
      EOS
    end

    def test_jl
      asm = Assembler.new
      asm.jl(rel32(0xff)) # JL rel32
      assert_compile(asm, <<~EOS)
        0x0: jl 0xff
      EOS
    end

    def test_jmp
      asm = Assembler.new
      label = asm.new_label('label')
      asm.jmp(label)       # JZ rel8
      asm.write_label(label)
      asm.jmp(rel32(0xff)) # JMP rel32
      asm.jmp([:rax, 8])   # JMP r/m64 (Mod 01: [reg]+disp8)
      asm.jmp(:rax)        # JMP r/m64 (Mod 11: reg)
      assert_compile(asm, <<~EOS)
        0x0: jmp 2
        0x2: jmp 0xff
        0x7: jmp qword ptr [rax + 8]
        0xa: jmp rax
      EOS
    end

    def test_jne
      asm = Assembler.new
      asm.jne(rel32(0xff)) # JNE rel32
      assert_compile(asm, <<~EOS)
        0x0: jne 0xff
      EOS
    end

    def test_jnz
      asm = Assembler.new
      asm.jnz(rel32(0xff)) # JNZ rel32
      assert_compile(asm, <<~EOS)
        0x0: jne 0xff
      EOS
    end

    def test_jo
      asm = Assembler.new
      asm.jo(rel32(0xff)) # JO rel32
      assert_compile(asm, <<~EOS)
        0x0: jo 0xff
      EOS
    end

    def test_jz
      asm = Assembler.new
      asm.jz(rel32(0xff)) # JZ rel32
      assert_compile(asm, <<~EOS)
        0x0: je 0xff
      EOS
    end

    def test_lea
      asm = Assembler.new
      asm.lea(:rax, [:rax, 8])      # LEA r64,m (Mod 01: [reg]+disp8)
      asm.lea(:rax, [:rax, 0xffff]) # LEA r64,m (Mod 10: [reg]+disp32)
      assert_compile(asm, <<~EOS)
        0x0: lea rax, [rax + 8]
        0x4: lea rax, [rax + 0xffff]
      EOS
    end

    def test_mov
      asm = Assembler.new
      asm.mov(:eax, DwordPtr[:rbx, 8])  # MOV r32 r/m32 (Mod 01: [reg]+disp8)
      asm.mov(:eax, 0x100)              # MOV r32, imm32 (Mod 11: reg)
      asm.mov(:rax, [:rbx])             # MOV r64, r/m64 (Mod 00: [reg])
      asm.mov(:rax, [:rbx, 8])          # MOV r64, r/m64 (Mod 01: [reg]+disp8)
      asm.mov(:rax, [:rbx, 0x100])      # MOV r64, r/m64 (Mod 10: [reg]+disp32)
      asm.mov(:rax, :rbx)               # MOV r64, r/m64 (Mod 11: reg)
      asm.mov(:rax, 0x100)              # MOV r/m64, imm32 (Mod 11: reg)
      asm.mov(:rax, 0x100000000)        # MOV r64, imm64
      asm.mov(DwordPtr[:rax, 8], 0x100) # MOV r/m32, imm32 (Mod 01: [reg]+disp8)
      asm.mov([:rax], 0x100)            # MOV r/m64, imm32 (Mod 00: [reg])
      asm.mov([:rax], :rbx)             # MOV r/m64, r64 (Mod 00: [reg])
      asm.mov([:rax, 8], 0x100)         # MOV r/m64, imm32 (Mod 01: [reg]+disp8)
      asm.mov([:rax, 8], :rbx)          # MOV r/m64, r64 (Mod 01: [reg]+disp8)
      asm.mov([:rax, 0x100], 0x100)     # MOV r/m64, imm32 (Mod 10: [reg]+disp32)
      asm.mov([:rax, 0x100], :rbx)      # MOV r/m64, r64 (Mod 10: [reg]+disp32)
      assert_compile(asm, <<~EOS)
        0x0: mov eax, dword ptr [rbx + 8]
        0x3: mov eax, 0x100
        0x8: mov rax, qword ptr [rbx]
        0xb: mov rax, qword ptr [rbx + 8]
        0xf: mov rax, qword ptr [rbx + 0x100]
        0x16: mov rax, rbx
        0x19: mov rax, 0x100
        0x20: movabs rax, 0x100000000
        0x2a: mov dword ptr [rax + 8], 0x100
        0x31: mov qword ptr [rax], 0x100
        0x38: mov qword ptr [rax], rbx
        0x3b: mov qword ptr [rax + 8], 0x100
        0x43: mov qword ptr [rax + 8], rbx
        0x47: mov qword ptr [rax + 0x100], 0x100
        0x52: mov qword ptr [rax + 0x100], rbx
      EOS
    end

    def test_or
      asm = Assembler.new
      asm.or(:rax, 0)         # OR r/m64, imm8 (Mod 11: reg)
      asm.or(:rax, 0xffff)    # OR r/m64, imm32 (Mod 11: reg)
      asm.or(:rax, [:rbx, 8]) # OR r64, r/m64 (Mod 01: [reg]+disp8)
      assert_compile(asm, <<~EOS)
        0x0: or rax, 0
        0x4: or rax, 0xffff
        0xb: or rax, qword ptr [rbx + 8]
      EOS
    end

    def test_push
      asm = Assembler.new
      asm.push(:rax) # PUSH r64
      assert_compile(asm, <<~EOS)
        0x0: push rax
      EOS
    end

    def test_pop
      asm = Assembler.new
      asm.pop(:rax) # POP r64
      assert_compile(asm, <<~EOS)
        0x0: pop rax
      EOS
    end

    def test_ret
      asm = Assembler.new
      asm.ret # RET
      assert_compile(asm, "0x0: ret \n")
    end

    def test_sar
      asm = Assembler.new
      asm.sar(:rax, 0) # SAR r/m64, imm8 (Mod 11: reg)
      assert_compile(asm, <<~EOS)
        0x0: sar rax, 0
      EOS
    end

    def test_sub
      asm = Assembler.new
      asm.sub(:rax, 8)    # SUB r/m64, imm8 (Mod 11: reg)
      asm.sub(:rax, :rbx) # SUB r/m64, r64 (Mod 11: reg)
      assert_compile(asm, <<~EOS)
        0x0: sub rax, 8
        0x4: sub rax, rbx
      EOS
    end

    def test_test
      asm = Assembler.new
      asm.test(BytePtr[:rax, 8], 16)   # TEST r/m8*, imm8 (Mod 01: [reg]+disp8)
      asm.test([:rax, 8], 8)           # TEST r/m64, imm32 (Mod 01: [reg]+disp8)
      asm.test([:rax, 0xffff], 0xffff) # TEST r/m64, imm32 (Mod 10: [reg]+disp32)
      asm.test(:rax, 0xffff)           # TEST r/m64, imm32 (Mod 11: reg)
      asm.test(:eax, :ebx)             # TEST r/m32, r32 (Mod 11: reg)
      asm.test(:rax, :rbx)             # TEST r/m64, r64 (Mod 11: reg)
      assert_compile(asm, <<~EOS)
        0x0: test byte ptr [rax + 8], 0x10
        0x4: test qword ptr [rax + 8], 8
        0xc: test qword ptr [rax + 0xffff], 0xffff
        0x17: test rax, 0xffff
        0x1e: test eax, ebx
        0x20: test rax, rbx
      EOS
    end

    def test_xor
      asm = Assembler.new
      asm.xor(:rax, :rbx)
      assert_compile(asm, <<~EOS)
        0x0: xor rax, rbx
      EOS
    end

    private

    def rel32(offset)
      @cb.write_addr + 0xff
    end

    def assert_compile(asm, expected)
      actual = compile(asm)
      assert_equal expected, actual, "---\n#{actual}---"
    end

    def compile(asm)
      start_addr = @cb.write_addr
      @cb.write(asm)
      end_addr = @cb.write_addr

      io = StringIO.new
      @cb.dump_disasm(start_addr, end_addr, io:, color: false, test: true)
      io.seek(0)
      disasm = io.read

      disasm.gsub!(/^  /, '')
      disasm.sub!(/\n\z/, '')
      disasm
    end
  end
end
