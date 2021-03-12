module YJIT
  def self.disasm(iseq)
    iseq = RubyVM::InstructionSequence.of(iseq)

    blocks = YJIT.blocks_for(iseq)
    return if blocks.empty?

    str = ""

    cs = YJIT::Disasm.new

    str << iseq.disasm
    str << "\n"

    # Sort the blocks by increasing addresses
    blocks.sort_by(&:address).each_with_index do |block, i|
      str << "== BLOCK #{i+1}/#{blocks.length}: #{block.code.length} BYTES, ISEQ RANGE [#{block.iseq_start_index},#{block.iseq_end_index}] ".ljust(80, "=")
      str << "\n"

      cs.disasm(block.code, block.address).each do |i|
        str << sprintf(
          "  %<address>08x:  %<instruction>s\t%<details>s\n",
          address: i.address,
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

  # Return a hash for statistics generated for the --yjit-stats command line option.
  # Return nil when option is not passed or unavailable.
  def self.runtime_stats
    # defined in yjit_iface.c
    Primitive.get_stat_counters
  end

  # Discard statistics collected for --yjit-stats.
  def self.reset_stats!
    # defined in yjit_iface.c
    Primitive.reset_stats_bang
  end

  class << self
    private

    # Format and print out counters
    def _print_stats
      counters = runtime_stats

      return unless counters

      $stderr.puts("***YJIT: Printing runtime counters from yjit.rb***")

      print_counters(counters, prefix: 'oswb_', prompt: 'opt_send_without_block exit reasons: ')
      print_counters(counters, prefix: 'leave_', prompt: 'leave exit reasons: ')
      print_counters(counters, prefix: 'getivar_', prompt: 'getinstancevariable exit reasons:')
    end

    def print_counters(counters, prefix:, prompt:)
      $stderr.puts(prompt)
      counters = counters.filter { |key, _| key.start_with?(prefix) }
      counters.filter! { |_, value| value != 0 }
      counters.transform_keys! { |key| key.to_s.delete_prefix(prefix) }

      if counters.empty?
        $stderr.puts("    (all relevant counters are zero)")
        return
      end

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
