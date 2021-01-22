module UJIT
  def self.disasm(iseq)
    if iseq.is_a? Method
        iseq = RubyVM::InstructionSequence.of(iseq)
    end

    blocks = UJIT.blocks_for(iseq)
    return if blocks.empty?

    str = ""

    cs = UJIT::Disasm.new

    str << iseq.disasm
    str << "\n"

    # Sort the blocks by increasing addresses
    blocks.sort_by(&:address).reverse.each do |block|
      str << "== ISEQ RANGE: [#{block.iseq_start_index},#{block.iseq_end_index}[ ".ljust(80, "=")
      str << "\n"

      cs.disasm(block.code, 0).each do |i|
        str << sprintf(
          "\t%<address>04X:\t%<instruction>s\t%<details>s\n",
          address: i.address,
          instruction: i.mnemonic,
          details: i.op_str
        )
      end
    end
    str
  end if defined?(Disasm)
end
