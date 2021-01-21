begin
require "crabstone"
require "stringio"

module UJIT
  def self.disasm(iseq)
    blocks = UJIT.blocks_for(iseq)
    return if blocks.empty?

    io = StringIO.new

    cs = Crabstone::Disassembler.new(Crabstone::ARCH_X86, Crabstone::MODE_64)

    io.puts iseq.disasm

    blocks.sort_by(&:address).reverse.each do |block|
      io.puts "== ISEQ RANGE: #{block.iseq_start_index} -> #{block.iseq_end_index} ".ljust(80, "=")
      cs.disasm(block.code, 0).each do |i|
        io.printf(
          "\t0x%<address>x:\t%<instruction>s\t%<details>s\n",
          address: i.address,
          instruction: i.mnemonic,
          details: i.op_str
        )
      end
    end
    io.string
  end
end
rescue
  puts "Please install crabstone like this:"
  puts "  $ brew install capstone"
  puts "  $ gem install capstone"
end
