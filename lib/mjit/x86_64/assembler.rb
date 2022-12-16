class RubyVM::MJIT::Assembler
  ByteWriter = RubyVM::MJIT::CType::Immediate.parse('char')

  def initialize
    @bytes = []
  end

  def compile(compiler) = with_dump_disasm(compiler) do
    RubyVM::MJIT::C.mjit_mark_writable
    write_bytes(compiler.write_addr, @bytes)
    RubyVM::MJIT::C.mjit_mark_executable

    compiler.write_pos += @bytes.size
    @bytes.clear
  end

  def add(_reg, imm)
    #           REX.W [83]  RSI   ib
    @bytes.push(0x48, 0x83, 0xc6, imm)
  end

  def mov(reg, val)
    case reg
    when :rax
      #           REX.W [C7]  RAX   imm32
      @bytes.push(0x48, 0xc7, 0xc0, val, 0x00, 0x00, 0x00)
    else
      #           REX.W [89]  [rdi+val],rsi
      @bytes.push(0x48, 0x89, 0x77, reg.last)
    end
  end

  def ret
    # Near return
    #           [C3]
    @bytes.push(0xc3)
  end

  private

  def with_dump_disasm(compiler)
    from = compiler.write_addr
    yield
    to = compiler.write_addr
    if RubyVM::MJIT::C.mjit_opts.dump_disasm && from < to
      RubyVM::MJIT::C.dump_disasm(from, to).each do |address, mnemonic, op_str|
        puts "  0x#{"%p" % address}: #{mnemonic} #{op_str}"
      end
    end
  end

  def write_bytes(addr, bytes)
    writer = ByteWriter.new(addr)
    # If you pack bytes containing \x00, Ruby fails to recognize bytes after \x00.
    # So writing byte by byte to avoid hitting that situation.
    bytes.each_with_index do |byte, index|
      writer[index] = byte
    end
  end
end
