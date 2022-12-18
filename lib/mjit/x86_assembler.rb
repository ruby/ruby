module RubyVM::MJIT
  class X86Assembler
    ByteWriter = CType::Immediate.parse('char')

    def initialize
      @bytes = []
    end

    def compile(addr)
      writer = ByteWriter.new(addr)
      # If you pack bytes containing \x00, Ruby fails to recognize bytes after \x00.
      # So writing byte by byte to avoid hitting that situation.
      @bytes.each_with_index do |byte, index|
        writer[index] = byte
      end
      @bytes.size
    ensure
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
  end
end
