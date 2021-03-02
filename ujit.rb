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

  # Return a hash for statistics generated for the --ujit-stats command line option.
  # Return nil when option is not passed or unavailable.
  def self.runtime_stats
    # defined in ujit_iface.c
    Primitive.get_stat_counters
  end

  class << self
    private

    # Format and print out counters
    def _print_stats
      counters = runtime_stats

      return unless counters

      $stderr.puts("***uJIT: Printing runtime counters from ujit.rb***")
      $stderr.puts("opt_send_without_block exit reasons: ")

      counters.filter! { |key, _| key.start_with?('oswb_') }
      counters.transform_keys! { |key| key.to_s.delete_prefix('oswb_') }

      counters = counters.to_a
      counters.sort_by! { |(_, counter_value)| counter_value }
      longest_name_length = counters.max_by { |(name, _)| name.length }.first.length
      total = counters.sum { |(_, counter_value)| counter_value }

      counters.reverse_each do |(name, value)|
        percentage = value.fdiv(total) * 100
        $stderr.printf("    %*s %10d (%4.1f%%)\n", longest_name_length, name, value, percentage);
      end
    end
  end
end
