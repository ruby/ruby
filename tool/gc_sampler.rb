#!/usr/bin/env ruby
# A minimal in-process GC sampler.
#
# A background thread wakes on a fixed wall-clock interval, snapshots the GC
# counters, and records the *delta* since the previous wake. to provide GC
# activity as a rate over time.
#
# When any profiler-backed data is available we tap GC::Profiler, but drain and
# .clear it every interval so its record buffer never grows unbounded. The raw
# per-GC records can also be retained for later dumping.

class GCSampler
  Caps = Struct.new(:rgengc_stat, :malloc_size, :prof_wall, :prof_pause_split, :prof_phase_wall, :prof_detail, :prof_rgengc, keyword_init: true)

  def self.initial_caps
    stat = GC.stat
    Caps.new(
      rgengc_stat: stat.key?(:total_promoted_count),
      malloc_size: GC.respond_to?(:malloc_allocated_size),
      prof_wall: false,
      prof_pause_split: false,
      prof_phase_wall: false,
      prof_detail: false,
      prof_rgengc: false,
    )
  end

  Col = Struct.new(:key, :head, :w, :fmt)

  def initialize(interval: 0.02, caps: GCSampler.initial_caps, raw_profile: true)
    @interval = interval
    @caps     = caps
    @samples  = []
    @profile_records = []
    @buf      = {}
    @running  = false
    @raw_profile = raw_profile
    @use_profiler = true
  end

  attr_reader :samples, :profile_records, :caps

  def start
    @running = true
    if @use_profiler
      @prof_was = GC::Profiler.enabled?
      GC::Profiler.enable
      GC::Profiler.clear
    end
    @t0   = mono
    @prev = snapshot
    @thread = Thread.new do
      while @running
        sleep @interval
        record
      end
    end
    self
  end

  def stop
    @running = false
    @thread&.join
    record
    if @use_profiler
      GC::Profiler.clear
      GC::Profiler.disable unless @prof_was
    end
    self
  end

  def run
    start
    yield
  ensure
    stop
  end

  def banner(io = $stdout)
    io.puts "GC sampler — #{RUBY_DESCRIPTION}"
    io.puts "optional data sources:"
    io.printf("  GC::Profiler raw records        : %s\n", yn(@raw_profile))
    io.printf("  GC::Profiler wall time fields   : %s\n", yn(@caps.prof_wall))
    io.printf("  GC::Profiler pause split fields : %s\n", yn(@caps.prof_pause_split))
    io.printf("  GC::Profiler phase wall fields  : %s\n", yn(@caps.prof_phase_wall))
    io.printf("  RGENGC_PROFILE (stat + profiler) : %s\n", yn(@caps.rgengc_stat || @caps.prof_rgengc))
    io.printf("  GC_PROFILE_MORE_DETAIL (profiler): %s\n", yn(@caps.prof_detail))
    io.printf("  MALLOC_ALLOCATED_SIZE (methods)  : %s\n", yn(@caps.malloc_size))
    io.puts  "  GC_PROFILE_DETAIL_MEMORY         : report-only — not samplable"
    io.puts
  end

  def report(io = $stdout)
    cols = build_columns
    io.puts(cols.map { |c| c.head.rjust(c.w) }.join(" "))
    @samples.each do |s|
      io.puts(cols.map { |c| format_cell(c, s) }.join(" "))
    end
  end

  def report_raw_profile(io = $stdout)
    return if @profile_records.empty?

    io.puts
    io.puts "raw GC::Profiler records:"
    @profile_records.each_with_index do |record, index|
      io.printf("[%d]\n", index)
      record.each do |key, value|
        io.printf("  %-26s %s\n", "#{key}:", value.inspect)
      end
    end
  end

  def summary(io = $stdout)
    return if @samples.empty?
    wall     = @samples.last[:t]
    wall_total_ms = wall * 1000.0
    gc_ms    = @samples.sum { _1[:gc_ms] }
    minors   = @samples.sum { _1[:minor] }
    majors   = @samples.sum { _1[:major] }
    gc_count = minors + majors
    io.puts
    io.printf("wall:        %.3f s\n", wall)
    io.printf("GCs:         %d minor + %d major\n", minors, majors)
    io.printf("objects:     %d allocated, %d freed\n", @samples.sum { _1[:alloc] }, @samples.sum { _1[:freed] })
    io.printf("GC CPU time: %.3f ms  (~%.1f%% of wall)\n", gc_ms, pct(gc_ms, wall_total_ms))
    if @caps.prof_wall
      wall_ms = @samples.sum { _1[:wall_ms].to_f }
      pause_ms = @samples.sum { _1[:pause_ms].to_f }
      max_pause_ms = @samples.filter_map { _1[:max_pause_ms] }.max || 0.0
      mean_pause = gc_count.zero? ? 0.0 : pause_ms / gc_count
      io.printf("GC wall:     %.3f ms  (~%.1f%% of wall)\n", wall_ms, pct(wall_ms, wall_total_ms))
      io.printf("GC pause:    %.3f ms total  (%.3f ms mean, %.3f ms max, per GC)\n", pause_ms, mean_pause, max_pause_ms)
      if @caps.prof_pause_split
        stop_ms = @samples.sum { _1[:stop_ms].to_f }
        stw_ms  = @samples.sum { _1[:stw_ms].to_f }
        io.printf("  stop/STW:  %.3f ms / %.3f ms  (ractor-stop ~%.1f%% of pause)\n",
                  stop_ms, stw_ms, pct(stop_ms, pause_ms))
      end
      if @caps.prof_phase_wall
        # Phase wall is bounded by pause; report against pause rather than
        # GC wall time because incremental-mark continuation lands in mark wall
        # but not in GC_WALL_TIME.
        mark_ms    = @samples.sum { _1[:markw_ms].to_f }
        sweep_ms   = @samples.sum { _1[:sweepw_ms].to_f }
        compact_ms = @samples.sum { _1[:compactw_ms].to_f }
        io.printf("  phase wall: mark %.3f ms (~%.1f%%) / sweep %.3f ms (~%.1f%%)",
                  mark_ms, pct(mark_ms, pause_ms), sweep_ms, pct(sweep_ms, pause_ms))
        io.printf(" / compact %.3f ms (~%.1f%%)", compact_ms, pct(compact_ms, pause_ms)) if compact_ms > 0.0
        io.printf("  (of pause)\n")
      end
    end
    if @caps.prof_detail
      io.printf("mark/sweep CPU: %.3f ms / %.3f ms\n", @samples.sum { _1[:mark_ms].to_f }, @samples.sum { _1[:sweep_ms].to_f })
    end
    if @caps.rgengc_stat
      io.printf("promoted:    %d objects to oldgen\n", @samples.sum { _1[:promoted] })
    end
  end

  private

  def yn(bool) = bool ? "yes" : "no"
  def pct(part, whole) = whole.to_f.zero? ? 0.0 : 100.0 * part / whole
  def mono = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def format_cell(col, row)
    value = row[col.key]
    return "-".rjust(col.w) if value.nil?

    format("%#{col.w}#{col.fmt}", value)
  end

  # Column set adapts to what this build exposes.
  def build_columns
    cols = [
      Col.new(:t,     "t(s)",  8, ".3f"),
      Col.new(:gc,    "gc",    4, "d"),
      Col.new(:minor, "minor", 5, "d"),
      Col.new(:major, "major", 5, "d"),
      Col.new(:alloc, "alloc", 10, "d"),
      Col.new(:freed, "freed", 10, "d"),
      Col.new(:live,  "live",  9, "d"),
      Col.new(:gc_ms, "gc_ms", 7, ".2f"),
    ]
    if @caps.prof_wall
      cols << Col.new(:wall_ms,  "wall_ms",  8, ".3f")
      cols << Col.new(:pause_ms, "pause_ms", 8, ".3f")
    end
    if @caps.prof_pause_split
      cols << Col.new(:stop_ms, "stop_ms", 8, ".3f")
      cols << Col.new(:stw_ms,  "stw_ms",  8, ".3f")
    end
    if @caps.prof_phase_wall
      cols << Col.new(:markw_ms,    "markW_ms",    8, ".3f")
      cols << Col.new(:sweepw_ms,   "sweepW_ms",   9, ".3f")
      cols << Col.new(:compactw_ms, "compactW_ms", 11, ".3f")
    end
    cols << Col.new(:mallocmb, "mallocMB", 8, ".1f") # total_malloc_bytes (always present)
    if @caps.prof_detail
      cols << Col.new(:mark_ms,  "mark_ms",  8, ".3f")
      cols << Col.new(:sweep_ms, "sweep_ms", 8, ".3f")
      cols << Col.new(:empty,    "emptyObj", 9, "d")
    end
    if @caps.rgengc_stat
      cols << Col.new(:promoted, "promoted", 9, "d")
      cols << Col.new(:shade,    "shade",    6, "d")
      cols << Col.new(:rem,      "remembrd", 9, "d")
    end
    if @caps.prof_rgengc && !@caps.rgengc_stat
      cols << Col.new(:old, "oldObj", 9, "d")
    end
    if @caps.malloc_size
      cols << Col.new(:malloc_live,  "mallocLiveMB", 12, ".2f")
      cols << Col.new(:malloc_count, "mallocAllocs", 12, "d")
    end
    cols << Col.new(:gc_by, "gc_by", 8, "s")
    cols
  end

  def snapshot
    GC.stat(@buf)
    s = {
      t:          mono,
      count:      @buf[:count],
      minor:      @buf[:minor_gc_count],
      major:      @buf[:major_gc_count],
      alloc:      @buf[:total_allocated_objects],
      freed:      @buf[:total_freed_objects],
      live:       @buf[:heap_live_slots],
      total_time: GC.total_time,
      malloc_b:   @buf[:total_malloc_bytes] || 0,
    }
    if @caps.rgengc_stat
      s[:promoted] = @buf[:total_promoted_count]
      s[:shade]    = @buf[:total_shade_operation_count]
      s[:rem]      = @buf[:total_remembered_normal_object_count]
    end
    if @caps.malloc_size
      s[:malloc_live]  = GC.malloc_allocated_size
      s[:malloc_count] = GC.malloc_allocations
    end
    s
  end

  def record
    cur  = snapshot
    gc_delta = cur[:count] - @prev[:count]
    row = {
      t:        (cur[:t] - @t0).round(3),
      gc:       gc_delta,
      minor:    cur[:minor] - @prev[:minor],
      major:    cur[:major] - @prev[:major],
      alloc:    cur[:alloc] - @prev[:alloc],
      freed:    cur[:freed] - @prev[:freed],
      live:     cur[:live],
      gc_ms:    (cur[:total_time] - @prev[:total_time]) / 1_000_000.0,
      mallocmb: cur[:malloc_b] / (1024.0 * 1024.0),
      gc_by:    gc_delta.zero? ? "-" : (GC.latest_gc_info[:gc_by] || "-"),
    }
    if @caps.rgengc_stat
      row[:promoted] = cur[:promoted] - @prev[:promoted]
      row[:shade]    = cur[:shade]    - @prev[:shade]
      row[:rem]      = cur[:rem]      - @prev[:rem]
    end
    if @caps.malloc_size
      row[:malloc_live]  = cur[:malloc_live] / (1024.0 * 1024.0)
      row[:malloc_count] = cur[:malloc_count]
    end
    drain_profiler(row) if @use_profiler
    @samples << row
    @prev = cur
  end

  # Aggregate the per-GC profiler records that accrued during this interval,
  # then clear so the buffer stays bounded.
  def drain_profiler(row)
    data = GC::Profiler.raw_data
    GC::Profiler.clear
    return if data.nil? || data.empty?
    @profile_records.concat(data.map(&:dup)) if @raw_profile
    @caps.prof_wall ||= data.any? { _1.key?(:GC_WALL_TIME) }
    @caps.prof_pause_split ||= data.any? { _1.key?(:GC_STOP_TIME) }
    @caps.prof_phase_wall ||= data.any? { _1.key?(:GC_MARK_WALL_TIME) }
    @caps.prof_detail ||= data.any? { _1.key?(:GC_MARK_TIME) }
    @caps.prof_rgengc ||= data.any? { _1.key?(:OLD_OBJECTS) }
    if @caps.prof_wall
      pauses = data.map { _1[:GC_PAUSE_TIME] || 0.0 }
      row[:wall_ms] = data.sum { _1[:GC_WALL_TIME] || 0.0 } * 1000.0
      row[:pause_ms] = pauses.sum * 1000.0
      row[:max_pause_ms] = (pauses.max || 0.0) * 1000.0
    end
    if @caps.prof_pause_split
      row[:stop_ms] = data.sum { _1[:GC_STOP_TIME] || 0.0 } * 1000.0
      row[:stw_ms] = data.sum { _1[:GC_STW_TIME] || 0.0 } * 1000.0
    end
    if @caps.prof_phase_wall
      row[:markw_ms]    = data.sum { _1[:GC_MARK_WALL_TIME]    || 0.0 } * 1000.0
      row[:sweepw_ms]   = data.sum { _1[:GC_SWEEP_WALL_TIME]   || 0.0 } * 1000.0
      row[:compactw_ms] = data.sum { _1[:GC_COMPACT_WALL_TIME] || 0.0 } * 1000.0
    end
    if @caps.prof_detail
      row[:mark_ms]  = data.sum { _1[:GC_MARK_TIME] || 0.0 }  * 1000.0
      row[:sweep_ms] = data.sum { _1[:GC_SWEEP_TIME] || 0.0 } * 1000.0
      row[:empty]    = data.sum { _1[:EMPTY_OBJECTS] || 0 }
    end
    if @caps.prof_rgengc && !@caps.rgengc_stat
      row[:old] = data.last[:OLD_OBJECTS]
    end
  end
end

USAGE = <<~USAGE
  Usage:
    #{$PROGRAM_NAME} SCRIPT [ARGS...]
    #{$PROGRAM_NAME} -e CODE [ARGS...]
USAGE

def parse_target(argv)
  case argv.first
  when "-e"
    abort USAGE if argv.size < 2

    code = argv[1]
    args = argv.drop(2)
    -> {
      ARGV.replace(args)
      $0 = "-e"
      eval(code, TOPLEVEL_BINDING, "-e", 1)
    }
  when "-h", "--help"
    puts USAGE
    exit true
  when nil
    abort USAGE
  else
    script = argv.first
    args = argv.drop(1)
    abort "#{script}: no such file" unless File.file?(script)

    -> {
      ARGV.replace(args)
      $0 = script
      load File.expand_path(script)
    }
  end
end

if __FILE__ == $0
  target = parse_target(ARGV.dup)
  GC.measure_total_time = true if GC.respond_to?(:measure_total_time=)
  dump_raw = ENV["RAW"] == "1"
  sampler = GCSampler.new(interval: 0.02, raw_profile: dump_raw)
  failure = nil
  exit_status = nil

  sampler.banner
  begin
    sampler.run { target.call }
  rescue SystemExit => error
    exit_status = error.status
  rescue Exception => error # rubocop:disable Lint/RescueException
    failure = error
  ensure
    sampler.report
    sampler.report_raw_profile if dump_raw
    sampler.summary
  end

  raise failure if failure
  exit exit_status unless exit_status.nil?
end
