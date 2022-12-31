module RubyVM::MJIT
  class CodeBlock
    # @param mem_block [Integer] JIT buffer address
    # @param mem_size  [Integer] JIT buffer size
    def initialize(mem_block:, mem_size:)
      @comments  = Hash.new { |h, k| h[k] = [] }
      @mem_block = mem_block
      @mem_size  = mem_size
      @write_pos = 0
    end

    # @param asm [RubyVM::MJIT::Assembler]
    def write(asm)
      return 0 if @write_pos + asm.size >= @mem_size

      start_addr = write_addr

      # Write machine code
      C.mjit_mark_writable
      @write_pos += asm.assemble(start_addr)
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

    private

    def write_addr
      @mem_block + @write_pos
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
  end
end
