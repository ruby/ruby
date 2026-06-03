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

RubyBuiltinType = {
  :RUBY_T_NONE     => 0x00, # /**< Non-object (swept etc.) */:
  :RUBY_T_OBJECT   => 0x01, # /**< @see struct ::RObject */
  :RUBY_T_CLASS    => 0x02, # /**< @see struct ::RClass and ::rb_cClass */
  :RUBY_T_MODULE   => 0x03, # /**< @see struct ::RClass and ::rb_cModule */
  :RUBY_T_FLOAT    => 0x04, # /**< @see struct ::RFloat */
  :RUBY_T_STRING   => 0x05, # /**< @see struct ::RString */
  :RUBY_T_REGEXP   => 0x06, # /**< @see struct ::RRegexp */
  :RUBY_T_ARRAY    => 0x07, # /**< @see struct ::RArray */
  :RUBY_T_HASH     => 0x08, # /**< @see struct ::RHash */
  :RUBY_T_STRUCT   => 0x09, # /**< @see struct ::RStruct */
  :RUBY_T_BIGNUM   => 0x0a, # /**< @see struct ::RBignum */
  :RUBY_T_FILE     => 0x0b, # /**< @see struct ::RFile */
  :RUBY_T_DATA     => 0x0c, # /**< @see struct ::RTypedData */
  :RUBY_T_MATCH    => 0x0d, # /**< @see struct ::RMatch */
  :RUBY_T_COMPLEX  => 0x0e, # /**< @see struct ::RComplex */
  :RUBY_T_RATIONAL => 0x0f, # /**< @see struct ::RRational */:
  :RUBY_T_NIL      => 0x11, # /**< @see ::RUBY_Qnil */
  :RUBY_T_TRUE     => 0x12, # /**< @see ::RUBY_Qtrue */
  :RUBY_T_FALSE    => 0x13, # /**< @see ::RUBY_Qfalse */
  :RUBY_T_SYMBOL   => 0x14, # /**< @see struct ::RSymbol */
  :RUBY_T_FIXNUM   => 0x15, # /**< Integers formerly known as Fixnums. */
  :RUBY_T_UNDEF    => 0x16, # /**< @see ::RUBY_Qundef */:
  :RUBY_T_IMEMO    => 0x1a, # /**< @see struct ::RIMemo */
  :RUBY_T_NODE     => 0x1b, # /**< @see struct ::RNode */
  :RUBY_T_ICLASS   => 0x1c, # /**< Hidden classes known as IClasses. */
  :RUBY_T_ZOMBIE   => 0x1d, # /**< @see struct ::RZombie */
  :RUBY_T_MOVED    => 0x1e, # /**< @see struct ::RMoved */
}

RUBY_T_MASK     = 0x1f

RubyFlags = {
  :RUBY_FL_WB_PROTECTED   => (1<<5),
  :RUBY_FL_UNUSED6        => (1<<6),
  :RUBY_FL_FINALIZE       => (1<<7),
  :RUBY_FL_SHAREABLE      => (1<<8),
  :RUBY_FL_WEAK_REFERENCE => (1<<9),
  :RUBY_FL_UNUSED10       => (1<<10),
  :RUBY_FL_FREEZE         => (1<<11),
}

def decode_flags(flags)
  decoded = {}
  decoded['builtin_type'] = RubyBuiltinType.key(flags & RUBY_T_MASK)
  decoded['flags'] = {}
  RubyFlags.each do |k, v|
    decoded['flags'][k.to_s] = (flags & v) != 0
  end
  decoded
end

class LogProcessor
  def initialize(verbose: false)
    @verbose = verbose
    @type_id_name = {}
    @start_time = nil
    @results = []
    @started = false
  end

  attr_accessor :started

  def process_line(line)
    if !@started
      if line == "====RUBY_TRACING_LOG_START===="
        @started = true
      end
      return
    end

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
    when 'gc_xmalloc'
      result[:args].update({
        n: args[0].to_i,
        size: args[1].to_i,
      })
    when 'gc_xcalloc'
      result[:args].update({
        n: args[0].to_i,
        size: args[1].to_i,
      })
    when 'gc_obj_new'
      obj = args[0].to_i
      flags_value = args[1].to_i
      decoded_flags = decode_flags(flags_value)
      result[:args].update({
        obj: obj,
        flags_value: flags_value,
      }).update(decoded_flags)
    when 'gc_obj_free'
      obj = args[0].to_i
      flags_value = args[1].to_i
      decoded_flags = decode_flags(flags_value)
      result[:args].update({
        obj: obj,
        flags_value: flags_value,
      }).update(decoded_flags)
    when 'GCEnterExit'
      event = args[0].to_i
      result[:args].update({
        event: GCEnterEvent.key(event)
      })
    when 'rts_set_running'
      old_thread = args[0].to_i
      new_thread = args[1].to_i
      if old_thread == 0
        result[:name] = 'RTS'
        result[:ph] = 'B'
        result[:args].update({
          thread: new_thread,
        })
      elsif new_thread == 0
        result[:name] = 'RTS'
        result[:ph] = 'E'
        result[:args].update({
          thread: old_thread,
        })
      else
        result[:args].update({
          old_thread:,
          new_thread:,
        })
      end
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
