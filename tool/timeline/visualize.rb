#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require 'pathname'
require 'zlib'

require_relative 'lib/tracepoint_defs'
require_relative 'lib/converter_defs'
require_relative 'lib/converter'

PROBE_NAME_TO_USDT = RubyTimelineTool::USDT_DEFS.values.flatten.to_h { |t| [t.probe_name, t] }

module FetchStore
  refine Hash do
    def fetch_store(key)
      if include?(key)
        self[key]
      else
        self[key] = yield
      end
    end
  end
end

using FetchStore

class LogProcessor
  def initialize(verbose: false)
    @verbose = verbose
    @type_id_name = {}
    @start_time = nil
    @results = []
    @current = Hash.new { |hash, key| hash[key] = {} }
    @started = false
  end

  attr_accessor :started

  def process_line(line)
    if !@started
      if line == '====RUBY_TRACING_LOG_START===='
        @started = true
      end
      return
    end

    if line.include?(',')
      process_log_line(line)
    else
      puts "Discarded line '#{line}'" if @verbose
    end
  end

  def output(outfile)
    json_str = JSON.generate(@results)
    Zlib::GzipWriter.open(outfile) do |gz|
      gz.write(json_str)
    end
  end

  private

  def process_log_line(line)
    parts = line.split(',')
    probe_name, pid, tid, ts = parts[...4]
    pid = pid.to_i
    tid = tid.to_i
    ts = resolve_time(ts.to_i)
    raw_args = parts[4...]

    puts "probe_name: #{probe_name}, pid: #{pid}, tid: #{tid}, ts: #{ts}, raw_args: #{raw_args}" if @verbose

    if @start_time.nil?
      @start_time = ts
    end

    usdt_def = PROBE_NAME_TO_USDT[probe_name]

    ph = usdt_def.ph
    vis_name = usdt_def.vis_name

    args = {}
    usdt_def.args.each_pair.zip(raw_args) do |arg_def, arg_val|
      arg_name, arg_converter = arg_def
      begin
        converted_val = RubyTimelineTool.convert_arg(arg_val, arg_converter)
      rescue
        puts "error converting argument #{arg_name}, value: [#{arg_val}]"
        puts "line: #{line}"
        raise
      end

      args[arg_name] = converted_val
    end

    result = { name: vis_name, ph:, pid:, tid:, ts:, args: }

    if ph == 'B' || ph == 'E'
      # Register the current block so that other events can "enrich" it.
      set_current_block(tid, result)
    end

    # Some results need special treatment.
    case vis_name
    when 'gc_mark_stacked_objects'
      enrich([:global, 'GCEnterExit'], [tid, 'gc_mark']) do |old_result|
        old_result[:args].fetch_store(:gc_mark_stacked_objects) do
          { popped_count: 0 }
        end[:popped_count] += args[:popped_count]
      end
    when 'rts_set_running'
      sched = args[0].to_i
      old_thread = args[1].to_i
      new_thread = args[2].to_i
      if old_thread == 0
        result[:name] = 'RTS'
        result[:ph] = 'B'
        result[:args].update({
          sched:,
          thread: new_thread,
        })
      elsif new_thread == 0
        result[:name] = 'RTS'
        result[:ph] = 'E'
        result[:args].update({
          sched:,
          thread: old_thread,
        })
      else
        result[:args].update({
          old_thread:,
          new_thread:,
        })
      end
    end

    if result[:ph] != 'meta'
      @results << result
    end
  end

  def resolve_time(ts)
    if @start_time.nil?
      @start_time = ts
    end
    (ts - @start_time) / 1000.0
  end

  def set_current(tid, key, value)
    @current[tid][key] = value
  end

  def get_current(tid, key)
    @current[tid][key]
  end

  def clear_current(tid, key)
    @current[tid].delete(key)
  end

  def set_current_block(tid, result)
    case result[:ph]
    when 'B'
      set_current(tid, result[:name], result)
    when 'E'
      clear_current(tid, result[:name])
    else
      raise "unexpected ph: #{result}"
    end
  end

  # Look up an entry in the `@current` hash so that
  # you can add more arguments or make adjustments to it.
  def enrich(*targets)
    targets.each do |target|
      case target
      in [tid, key]
        result = @current[tid][key]
        if !result.nil?
          yield result
        end
      end
    end
  end
end

def main
  options = {}

  OptionParser.new do |parser|
    parser.on('-v', '--verbose', TrueClass, 'Print verbose messages.  For debugging.')
    parser.on('-d', '--dry-run', TrueClass, 'Dry run. DO not actually write into output file.')
  end.parse!(into: options)

  input = ARGV[0]
  if input.nil?
    raise 'Need positional argument'
  end

  input_path = Pathname.new(input)
  if !input_path.file?
    raise "File #{input_path} does not exist"
  end

  output_path = input_path.dirname / "#{input_path.basename}.json.gz"

  log_processor = LogProcessor.new(verbose: options[:verbose])

  input_path.each_line(chomp: true) do |line|
    log_processor.process_line(line)
  end

  if options[:'dry-run']
    puts "Dry run.  Output file: #{output_path}"
  else
    puts "Writing to output file: #{output_path}"
    log_processor.output(output_path)
  end
end

main
