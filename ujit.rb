module UJIT
  def omg
  end

  def self.disasm(iseq)
    blocks = UJIT.blocks_for(iseq)
    return if blocks.empty?

    str = ""

    cs = UJIT::Disasm.open(UJIT::Disasm::ARCH_X86, UJIT::Disasm::MODE_64)

    str << iseq.disasm
    str << "\n"

    blocks.sort_by(&:address).reverse.each do |block|
      str << "== ISEQ RANGE: #{block.iseq_start_index} -> #{block.iseq_end_index} ".ljust(80, "=")
      str << "\n"

      cs.disasm(block.code, 0).each do |i|
        str << sprintf(
          "\t0x%<address>x:\t%<instruction>s\t%<details>s\n",
          address: i.address,
          instruction: i.mnemonic,
          details: i.op_str
        )
      end
    end
    str
  end
end
