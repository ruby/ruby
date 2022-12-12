class RubyVM::MJIT::Assembler
  ByteWriter = RubyVM::MJIT::CType::Immediate.parse('char')

  def initialize
    @bytes = []
  end

  def compile(compiler)
    RubyVM::MJIT::C.mjit_mark_writable
    write_bytes(compiler.write_addr, @bytes)
    RubyVM::MJIT::C.mjit_mark_executable

    compiler.write_pos += @bytes.size
    @bytes.clear
  end

  def mov(_reg, val)
    @bytes.push(0xb8, val, 0x00, 0x00, 0x00)
  end

  def ret
    @bytes.push(0xc3)
  end

  private

  def write_bytes(addr, bytes)
    writer = ByteWriter.new(addr)
    # If you pack bytes containing \x00, Ruby fails to recognize bytes after \x00.
    # So writing byte by byte to avoid hitting that situation.
    bytes.each_with_index do |byte, index|
      writer[index] = byte
    end
  end
end
