#!/usr/bin/env ruby

class JITPerf
  INTERPRETER_SYMBOLS = [
    "rb_call0",
    "callable_method_entry_or_negative",
    "invoke_block_from_c_bh",
    "rb_funcallv_scope",
    "setup_parameters_complex",
    "rb_yield",
  ].freeze

  def initialize
    @total_cycles = 0
    @category_cycles = Hash.new(0)
    @detailed_category_cycles = Hash.new { |hash, category| hash[category] = Hash.new(0) }
    @categories = {}
  end

  def read(path)
    File.foreach(path).with_index(1) do |line, lineno|
      next if line.strip.empty?

      process_event(parse_line(line))
    rescue ArgumentError => error
      abort "#{path}:#{lineno}: #{error.message}"
    end
  rescue SystemCallError => error
    abort "#{path}: #{error.message}"
  end

  def print_report
    return if @total_cycles == 0

    puts "Aggregated Event Data:"
    puts format("%-20s %-50s %20s %15s", "[dso]", "[symbol or category]", "[top-most cycle ratio]", "[num cycles]")

    most_common(@category_cycles).each do |category, cycles|
      ratio = cycles.to_f / @total_cycles * 100
      dsos = @detailed_category_cycles[category].each_key.map(&:first).uniq
      dso_display = dsos.length == 1 ? dsos.first : "Multiple DSOs"
      puts format("%-20s %-50s %20.2f%% %15d", dso_display, truncate_symbol(category), ratio, cycles)
    end

    most_common(@category_cycles).each do |category, _cycles|
      next unless @categories.key?(category)

      symbols = @detailed_category_cycles[category]
      category_total = symbols.values.sum
      category_ratio = category_total.to_f / @total_cycles * 100

      puts
      puts format("Category: %s (%.2f%%)", category, category_ratio)
      puts format("%-20s %-50s %20s %15s", "[dso]", "[symbol]", "[top-most cycle ratio]", "[num cycles]")

      most_common(symbols).each do |(dso, symbol), cycles|
        symbol_ratio = cycles.to_f / category_total * 100
        puts format("%-20s %-50s %20.2f%% %15d", dso, truncate_symbol(symbol), symbol_ratio, cycles)
      end
    end
  end

  private

  def parse_line(line)
    fields = line.split(nil, 7)
    raise ArgumentError, "unexpected perf script line: #{line.chomp}" if fields.length < 7

    begin
      period = Integer(fields[3])
    rescue ArgumentError, TypeError
      raise ArgumentError, "unexpected sample period in perf script line: #{line.chomp}"
    end

    dso_start = fields[6].rindex(" (")
    raise ArgumentError, "missing dso in perf script line: #{line.chomp}" unless dso_start

    dso_with_suffix = fields[6][(dso_start + 2)..-1]
    dso_end = dso_with_suffix.index(")")
    raise ArgumentError, "missing dso terminator in perf script line: #{line.chomp}" unless dso_end

    symbol = fields[6][0...dso_start].split("+", 2).first
    dso = dso_with_suffix[0...dso_end]

    [dso, symbol, period]
  end

  def process_event(event)
    full_dso, symbol, cycles = event
    dso = File.basename(full_dso || "Unknown_dso")
    symbol ||= "[unknown]"

    @total_cycles += cycles

    category = categorize_symbol(dso, symbol)
    @category_cycles[category] += cycles
    @detailed_category_cycles[category][[dso, symbol]] += cycles

    @categories[category] = true if category.start_with?("[") && category.end_with?("]")
  end

  def truncate_symbol(symbol, max_length = 50)
    symbol.length <= max_length ? symbol : "#{symbol[0...(max_length - 3)]}..."
  end

  def categorize_symbol(dso, symbol)
    if dso == "sqlite3_native.so"
      "[sqlite3]"
    elsif symbol.include?("SHA256")
      "[sha256]"
    elsif symbol.start_with?("[JIT] gen_send")
      "[JIT send]"
    elsif symbol.start_with?("[JIT]") || symbol.start_with?("ZJIT: ") || dso.start_with?("perf-")
      "[JIT code]"
    elsif symbol.include?("::") || symbol.start_with?("_ZN4yjit") || symbol.start_with?("_ZN4zjit")
      "[JIT compile]"
    elsif symbol.start_with?("rb_vm_") || symbol.start_with?("vm_") || INTERPRETER_SYMBOLS.include?(symbol)
      "[interpreter]"
    elsif symbol.start_with?("rb_hash_") || symbol.start_with?("hash_")
      "[rb_hash_*]"
    elsif symbol.start_with?("rb_ary_") || symbol.start_with?("ary_")
      "[rb_ary_*]"
    elsif symbol.start_with?("rb_str_") || symbol.start_with?("str_")
      "[rb_str_*]"
    elsif symbol.start_with?("rb_sym") || symbol.start_with?("sym_")
      "[rb_sym_*]"
    elsif symbol.start_with?("rb_st_") || symbol.start_with?("st_")
      "[rb_st_*]"
    elsif symbol.start_with?("rb_ivar_") || symbol.include?("shape")
      "[ivars]"
    elsif symbol.include?("match") || symbol.start_with?("rb_reg") || symbol.start_with?("onig")
      "[regexp]"
    elsif symbol.include?("alloc") || symbol.include?("free") || symbol.include?("gc")
      "[GC]"
    elsif symbol.include?("pthread") && symbol.include?("lock")
      "[pthread lock]"
    else
      symbol
    end
  end

  def most_common(counter)
    counter.each.with_index
      .sort_by { |((_key, cycles), index)| [-cycles, index] }
      .map(&:first)
  end
end

if ARGV.length != 1
  abort "Usage: #{File.basename($PROGRAM_NAME)} <perf-script-output>"
end

jit_perf = JITPerf.new
jit_perf.read(ARGV[0])
jit_perf.print_report
