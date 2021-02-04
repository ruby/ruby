module UJIT
  def self.disasm(iseq)
    iseq = RubyVM::InstructionSequence.of(iseq)

    blocks = UJIT.blocks_for(iseq)
    return if blocks.empty?

    str = ""

    cs = UJIT::Disasm.new

    str << iseq.disasm
    str << "\n"

    # Sort the blocks by increasing addresses
    blocks.sort_by(&:address).each_with_index do |block, i|
      str << "== BLOCK #{i+1}/#{blocks.length}: #{block.code.length} BYTES, ISEQ RANGE [#{block.iseq_start_index},#{block.iseq_end_index}[ ".ljust(80, "=")
      str << "\n"

      cs.disasm(block.code, 0).each do |i|
        str << sprintf(
          "  %<address>08X:  %<instruction>s\t%<details>s\n",
          address: block.address + i.address,
          instruction: i.mnemonic,
          details: i.op_str
        )
      end
    end

    block_sizes = blocks.map { |block| block.code.length }
    total_bytes = block_sizes.reduce(0, :+)
    str << "\n"
    str << "Total code size: #{total_bytes} bytes"
    str << "\n"

    str
  end if defined?(Disasm)
end
