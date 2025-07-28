#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require 'pathname'
require 'zlib'

RubyInternalEvent = {
  :NEWOBJ        =>  0x100000,  # /**< Object allocated. */
  :FREEOBJ       =>  0x200000,  # /**< Object swept. */
  :GC_START      =>  0x400000,  # /**< GC started. */
  :GC_END_MARK   =>  0x800000,  # /**< GC ended mark phase. */
  :GC_END_SWEEP  =>  0x1000000, # /**< GC ended sweep phase. */
  :GC_ENTER      =>  0x2000000, # /**< `gc_enter()` is called. */
  :GC_EXIT       =>  0x4000000, # /**< `gc_exit()` is called. */
}

GCEnterEvent = {
  :start        => 0,
  :continue     => 1,
  :rest         => 2,
  :finalizer    => 3,
}

class LogProcessor
  def initialize(verbose: false)
    @verbose = verbose
    @type_id_name = {}
    @start_time = nil
    @results = []
  end

  def process_line(line)
    if line.include?(',')
      process_log_line(line)
    else
      if @verbose
        puts "Discarded line '#{line}'"
      end
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
    name, ph, tid, ts = parts[...4]
    tid = tid.to_i
    ts = resolve_time(ts.to_i)
    args = parts[4...]

    puts "name: #{name}, ph: #{ph}, tid: #{tid}, ts: #{ts}, args: #{args}" if @verbose

    if @start_time.nil?
      @start_time = ts
    end

    result = {
      name: name,
      ph: ph,
      tid: tid,
      ts: ts,
      args: {},
    }

    case name
    when 'gc_event_hook'
      event = args[0].to_i
      result[:args].update({
        event: event
      })
      result[:name] = RubyInternalEvent.key(event)
    when 'GCEnterExit'
      event = args[0].to_i
      result[:args].update({
        event: GCEnterEvent.key(event)
      })
    end

    @results << result
  end

  def resolve_time(ts)
    if @start_time.nil?
      @start_time = ts
    end
    (ts - @start_time) / 1000.0
  end
end

def main()
  options = {}

  OptionParser.new do |parser|
    parser.on('-v', '--verbose', TrueClass, 'Print verbose messages.  For debugging.')
    parser.on('-d', '--dry-run', TrueClass, 'Dry run. DO not actually write into output file.')
  end.parse!(into: options)

  input = ARGV[0]
  if input.nil?
    raise "Need positional argument"
  end

  input_path = Pathname.new(input)
  if !input_path.file?
    raise "File #{input_path} does not exist"
  end

  output_path = input_path.dirname / (input_path.basename.to_s + '.json.gz')

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

main()
