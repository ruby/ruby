#
# benchmark.rb - a performance benchmarking library 
# 
# $Id$
# 
# Created by Gotoken (gotoken@notwork.org). 
#
# Documentation by Gotoken (original RD), Lyle Johnson (RDoc conversion), and
# Gavin Sinclair (editing). 
#
# == Overview
#
# The Benchmark module provides methods for benchmarking Ruby code, giving
# detailed reports on the time taken for each task.
#


#
# The Benchmark module provides methods to measure and report the time
# used to execute Ruby code.  Read on for illustrative examples.
# 
# == Examples
# 
#
# === Example 1
#
# To measure the time to construct the string given by the expression
# <tt>"a"*1_000_000</tt>:
#
#       require 'benchmark'
#
#       puts Benchmark.measure { "a"*1_000_000 }
# 
# On my machine (FreeBSD 3.2 on P5100MHz) this reported as follows:
# 
#       1.166667   0.050000   1.216667 (  0.571355)
# 
# This report shows the user CPU time, system CPU time, the sum of the user and
# system CPU times, and the elapsed real time. The unit of time is seconds.
# 
#
# === Example 2
#
# To do some experiments sequentially, the #bm method is useful:
#
#       require 'benchmark'
#
#       n = 50000
#       Benchmark.bm do |x|
#         x.report { for i in 1..n; a = "1"; end }
#         x.report { n.times do   ; a = "1"; end }
#         x.report { 1.upto(n) do ; a = "1"; end }
#       end
# 
# The result:
#
#              user     system      total        real
#          1.033333   0.016667   1.016667 (  0.492106)
#          1.483333   0.000000   1.483333 (  0.694605)
#          1.516667   0.000000   1.516667 (  0.711077)
#
#
# === Example 3
#
# Continuing the previous example, to put a label in each report:
#
#       require 'benchmark'
#
#       n = 50000
#       Benchmark.bm(7) do |x|
#         x.report("for:")   { for i in 1..n; a = "1"; end }
#         x.report("times:") { n.times do   ; a = "1"; end }
#         x.report("upto:")  { 1.upto(n) do ; a = "1"; end }
#       end
# 
# The argument to #bm (7) specifies the offset of each report according to the
# longest label.
# 
# The result:
# 
#                     user     system      total        real
#        for:     1.050000   0.000000   1.050000 (  0.503462)
#        times:   1.533333   0.016667   1.550000 (  0.735473)
#        upto:    1.500000   0.016667   1.516667 (  0.711239)
# 
#
# === Example 4
# 
# The times for some benchmarks depend on the order in which items are run.
# These differences are due to the cost of memory allocation and garbage
# collection.
#
# To avoid these discrepancies, the #bmbm method is provided.  For example, to
# compare ways for sort an array of floats:
#
#       require 'benchmark'
#       
#       array = (1..1000000).map { rand }
#       
#       Benchmark.bmbm do |x|
#         x.report("sort!") { array.dup.sort! }
#         x.report("sort")  { array.dup.sort  }
#       end
# 
# The result:
# 
#        Rehearsal -----------------------------------------
#        sort!  11.928000   0.010000  11.938000 ( 12.756000)
#        sort   13.048000   0.020000  13.068000 ( 13.857000)
#        ------------------------------- total: 25.006000sec
#        
#                    user     system      total        real
#        sort!  12.959000   0.010000  12.969000 ( 13.793000)
#        sort   12.007000   0.000000  12.007000 ( 12.791000)
#
#
# === Example 5
#
# To report statistics of sequential experiments with unique labels,
# #benchmark is available:
#
#       require 'benchmark'
#
#       n = 50000
#       Benchmark.benchmark(" "*7 + CAPTION, 7, FMTSTR, ">total:", ">avg:") do |x|
#         tf = x.report("for:")   { for i in 1..n; a = "1"; end }
#         tt = x.report("times:") { n.times do   ; a = "1"; end }
#         tu = x.report("upto:")  { 1.upto(n) do ; a = "1"; end }
#         [tf+tt+tu, (tf+tt+tu)/3]
#       end
# 
# The result:
# 
#                     user     system      total        real
#        for:     1.016667   0.016667   1.033333 (  0.485749)
#        times:   1.450000   0.016667   1.466667 (  0.681367)
#        upto:    1.533333   0.000000   1.533333 (  0.722166)
#        >total:  4.000000   0.033333   4.033333 (  1.889282)
#        >avg:    1.333333   0.011111   1.344444 (  0.629761)
# 
module Benchmark

  # BENCHMARK_VERSION is version string containing the last modification
  # date (YYYY-MM-DD). 
  BENCHMARK_VERSION = "2002-04-25"

  def Benchmark::times() # :nodoc:
      Process::times()
  end


  #
  # Reports the time required to execute one or more blocks of code.
  #
  # _Note_: Other methods provide a simpler interface to this one, and are
  # suitable for nearly all benchmarking requirements.  See the examples in
  # Benchmark, and the #bm and #bmbm methods.
  #
  # Example: 
  #
  #     require 'benchmark'
  #     include Benchmark          # we need the CAPTION and FMTSTR constants 
  #
  #     n = 50000
  #     Benchmark.benchmark(" "*7 + CAPTION, 7, FMTSTR, ">total:", ">avg:") do |x|
  #       tf = x.report("for:")   { for i in 1..n; a = "1"; end }
  #       tt = x.report("times:") { n.times do   ; a = "1"; end }
  #       tu = x.report("upto:")  { 1.upto(n) do ; a = "1"; end }
  #       [tf+tt+tu, (tf+tt+tu)/3]
  #     end
  # 
  # The result:
  # 
  #                     user     system      total        real
  #        for:     1.016667   0.016667   1.033333 (  0.485749)
  #        times:   1.450000   0.016667   1.466667 (  0.681367)
  #        upto:    1.533333   0.000000   1.533333 (  0.722166)
  #        >total:  4.000000   0.033333   4.033333 (  1.889282)
  #        >avg:    1.333333   0.011111   1.344444 (  0.629761)
  # 
  # The parameters accepted are as follows:
  # 
  # _caption_::
  #   A string printed once before execution of the given block. 
  # 
  # _label_width_::
  #   An integer used as an offset in each report. 
  # 
  # _fmtstr_::
  #   A string used to format each measurement. See Benchmark::Tms#format.
  # 
  # _labels_::
  #   The remaining parameters are used as prefix of the format to the
  #   value of block; see the example above.
  #
  # This method yields a Benchmark::Report object. 
  # 
  def benchmark(caption = "", label_width = nil, fmtstr = nil, *labels) # :yield: report
    sync = STDOUT.sync
    STDOUT.sync = true
    label_width ||= 0
    fmtstr ||= FMTSTR
    raise ArgumentError, "no block" unless iterator?
    print caption
    results = yield(Report.new(label_width, fmtstr))
    Array === results and results.grep(Tms).each {|t|
      print((labels.shift || t.label || "").ljust(label_width), 
            t.format(fmtstr))
    }
    STDOUT.sync = sync
  end


  # 
  # A simple interface to #benchmark, #bm is suitable for sequential reports
  # with labels.  For example:
  # 
  #     require 'benchmark'
  #
  #     n = 50000
  #     Benchmark.bm(7) do |x|
  #       x.report("for:")   { for i in 1..n; a = "1"; end }
  #       x.report("times:") { n.times do   ; a = "1"; end }
  #       x.report("upto:")  { 1.upto(n) do ; a = "1"; end }
  #     end
  # 
  # The argument to #bm (7) specifies the offset of each report according to the
  # longest label.
  # 
  # This reports as follows:
  # 
  #                     user     system      total        real
  #        for:     1.050000   0.000000   1.050000 (  0.503462)
  #        times:   1.533333   0.016667   1.550000 (  0.735473)
  #        upto:    1.500000   0.016667   1.516667 (  0.711239)
  #
  # The labels are optional. 
  # 
  def bm(label_width = 0, *labels, &blk) # :yield: report
    benchmark(" "*label_width + CAPTION, label_width, FMTSTR, *labels, &blk)
  end


  # 
  # Similar to #bm, but designed to prevent memory allocation and garbage
  # collection from influencing the result.  It works like this:
  # 
  # 1. The _rehearsal_ step runs all items in the job list to allocate
  #    enough memory.
  # 2. Before each measurement, invokes GC.start to prevent the influence of
  #    previous job. 
  #
  # If the specified _label_width_ is less than the width of the widest label
  # passed as an argument to #item, the latter is used.  (Because #bmbm is a
  # 2-pass procedure, this is possible.)  Therefore you do not really need to
  # specify a label width.
  #
  # For example:
  #
  #       require 'benchmark'
  #       
  #       array = (1..1000000).map { rand }
  #       
  #       Benchmark.bmbm do |x|
  #         x.report("sort!") { array.dup.sort! }
  #         x.report("sort")  { array.dup.sort  }
  #       end
  # 
  # The result:
  # 
  #        Rehearsal -----------------------------------------
  #        sort!  11.928000   0.010000  11.938000 ( 12.756000)
  #        sort   13.048000   0.020000  13.068000 ( 13.857000)
  #        ------------------------------- total: 25.006000sec
  #        
  #                    user     system      total        real
  #        sort!  12.959000   0.010000  12.969000 ( 13.793000)
  #        sort   12.007000   0.000000  12.007000 ( 12.791000)
  #
  # #bmbm yields a Benchmark::Job object and returns an array of one
  # Benchmark::Tms objects.
  #
  def bmbm(width = 0, &blk) # :yield: job
    job = Job.new(width)
    yield(job)
    width = job.width
    sync = STDOUT.sync
    STDOUT.sync = true

    # rehearsal
    print "Rehearsal "
    puts '-'*(width+CAPTION.length - "Rehearsal ".length)
    list = []
    job.list.each{|label,item|
      print(label.ljust(width))
      res = Benchmark::measure(&item)
      print res.format()
      list.push res
    }
    sum = Tms.new; list.each{|i| sum += i}
    ets = sum.format("total: %tsec")
    printf("%s %s\n\n",
           "-"*(width+CAPTION.length-ets.length-1), ets)
    
    # take
    print ' '*width, CAPTION
    list = []
    ary = []
    job.list.each{|label,item|
      GC::start
      print label.ljust(width)
      res = Benchmark::measure(&item)
      print res.format()
      ary.push res
      list.push [label, res]
    }

    STDOUT.sync = sync
    ary
  end

  # 
  # Returns the time used to execute the given block as a
  # Benchmark::Tms object.
  #
  def measure(label = "") # :yield:
    t0, r0 = Benchmark.times, Time.now
    yield
    t1, r1 = Benchmark.times, Time.now
    Benchmark::Tms.new(t1.utime  - t0.utime, 
                       t1.stime  - t0.stime, 
                       t1.cutime - t0.cutime, 
                       t1.cstime - t0.cstime, 
                       r1.to_f - r0.to_f,
                       label)
  end

  #
  # Returns the elapsed real time used to execute the given block.
  #
  def realtime(&blk) # :yield:
    Benchmark::measure(&blk).real
  end



  #
  # A Job is a sequence of labelled blocks to be processed by the
  # Benchmark.bmbm method.  It is of little direct interest to the user.
  #
  class Job
    #
    # Returns an initialized Job instance.
    # Usually, one doesn't call this method directly, as new
    # Job objects are created by the #bmbm method.
    # _width_ is a initial value for the label offset used in formatting;
    # the #bmbm method passes its _width_ argument to this constructor. 
    # 
    def initialize(width)
      @width = width
      @list = []
    end

    #
    # Registers the given label and block pair in the job list.
    #
    def item(label = "", &blk) # :yield:
      raise ArgmentError, "no block" unless block_given?
      label.concat ' '
      w = label.length
      @width = w if @width < w
      @list.push [label, blk]
      self
    end

    alias report item
    
    # An array of 2-element arrays, consisting of label and block pairs.
    attr_reader :list
    
    # Length of the widest label in the #list, plus one.  
    attr_reader :width
  end

  module_function :benchmark, :measure, :realtime, :bm, :bmbm



  #
  # This class is used by the Benchmark.benchmark and Benchmark.bm methods.
  # It is of little direct interest to the user.
  #
  class Report
    #
    # Returns an initialized Report instance.
    # Usually, one doesn't call this method directly, as new
    # Report objects are created by the #benchmark and #bm methods. 
    # _width_ and _fmtstr_ are the label offset and 
    # format string used by Tms#format. 
    # 
    def initialize(width = 0, fmtstr = nil)
      @width, @fmtstr = width, fmtstr
    end

    #
    # Prints the _label_ and measured time for the block,
    # formatted by _fmt_. See Tms#format for the
    # formatting rules.
    #
    def item(label = "", *fmt, &blk) # :yield:
      print label.ljust(@width)
      res = Benchmark::measure(&blk)
      print res.format(@fmtstr, *fmt)
      res
    end

    alias report item
  end



  #
  # A data object, representing the times associated with a benchmark
  # measurement.
  #
  class Tms
    CAPTION = "      user     system      total        real\n"
    FMTSTR = "%10.6u %10.6y %10.6t %10.6r\n"

    # User CPU time
    attr_reader :utime
    
    # System CPU time
    attr_reader :stime
   
    # User CPU time of children
    attr_reader :cutime
    
    # System CPU time of children
    attr_reader :cstime
    
    # Elapsed real time
    attr_reader :real
    
    # Total time, that is _utime_ + _stime_ + _cutime_ + _cstime_ 
    attr_reader :total
    
    # Label
    attr_reader :label

    #
    # Returns a initialized Tms object which has
    # _u_ as the user CPU time, _s_ as the system CPU time, 
    # _cu_ as the childrens' user CPU time, _cs_ as the childrens'
    # system CPU time, _real_ as the elapsed real time and _l_
    # as the label. 
    # 
    def initialize(u = 0.0, s = 0.0, cu = 0.0, cs = 0.0, real = 0.0, l = nil)
      @utime, @stime, @cutime, @cstime, @real, @label = u, s, cu, cs, real, l
      @total = @utime + @stime + @cutime + @cstime
    end

    # 
    # Returns a new Tms object whose times are the sum of the times for this
    # Tms object, plus the time required to execute the code block (_blk_).
    # 
    def add(&blk) # :yield:
      self + Benchmark::measure(&blk) 
    end

    # 
    # An in-place version of #add.
    # 
    def add!
      t = Benchmark::measure(&blk) 
      @utime  = utime + t.utime
      @stime  = stime + t.stime
      @cutime = cutime + t.cutime
      @cstime = cstime + t.cstime
      @real   = real + t.real
      self
    end

    # 
    # Returns a new Tms object obtained by memberwise summation
    # of the individual times for this Tms object with those of the other
    # Tms object.
    # This method and #/() are useful for taking statistics. 
    # 
    def +(other); memberwise(:+, other) end
    
    #
    # Returns a new Tms object obtained by memberwise subtraction
    # of the individual times for the other Tms object from those of this
    # Tms object.
    #
    def -(other); memberwise(:-, other) end
    
    #
    # Returns a new Tms object obtained by memberwise multiplication
    # of the individual times for this Tms object by _x_.
    #
    def *(x); memberwise(:*, x) end

    # 
    # Returns a new Tms object obtained by memberwise division
    # of the individual times for this Tms object by _x_.
    # This method and #+() are useful for taking statistics. 
    # 
    def /(x); memberwise(:/, x) end

    #
    # Returns the contents of this Tms object as
    # a formatted string, according to a format string
    # like that passed to Kernel.format. In addition, #format
    # accepts the following extensions:
    #
    # <tt>%u</tt>::     Replaced by the user CPU time, as reported by Tms#utime.
    # <tt>%y</tt>::     Replaced by the system CPU time, as reported by #stime (Mnemonic: y of "s*y*stem")
    # <tt>%U</tt>::     Replaced by the childrens' user CPU time, as reported by Tms#cutime 
    # <tt>%Y</tt>::     Replaced by the childrens' system CPU time, as reported by Tms#cstime
    # <tt>%t</tt>::     Replaced by the total CPU time, as reported by Tms#total
    # <tt>%r</tt>::     Replaced by the elapsed real time, as reported by Tms#real
    # <tt>%n</tt>::     Replaced by the label string, as reported by Tms#label (Mnemonic: n of "*n*ame")
    # 
    # If _fmtstr_ is not given, FMTSTR is used as default value, detailing the
    # user, system and real elapsed time.
    # 
    def format(arg0 = nil, *args)
      fmtstr = (arg0 || FMTSTR).dup
      fmtstr.gsub!(/(%[-+\.\d]*)n/){"#{$1}s" % label}
      fmtstr.gsub!(/(%[-+\.\d]*)u/){"#{$1}f" % utime}
      fmtstr.gsub!(/(%[-+\.\d]*)y/){"#{$1}f" % stime}
      fmtstr.gsub!(/(%[-+\.\d]*)U/){"#{$1}f" % cutime}
      fmtstr.gsub!(/(%[-+\.\d]*)Y/){"#{$1}f" % cstime}
      fmtstr.gsub!(/(%[-+\.\d]*)t/){"#{$1}f" % total}
      fmtstr.gsub!(/(%[-+\.\d]*)r/){"(#{$1}f)" % real}
      arg0 ? Kernel::format(fmtstr, *args) : fmtstr
    end

    # 
    # Same as #format.
    # 
    def to_s
      format
    end

    # 
    # Returns a new 6-element array, consisting of the
    # label, user CPU time, system CPU time, childrens'
    # user CPU time, childrens' system CPU time and elapsed
    # real time.
    # 
    def to_a
      [@label, @utime, @stime, @cutime, @cstime, @real]
    end

    protected
    def memberwise(op, x)
      case x
      when Benchmark::Tms
        Benchmark::Tms.new(utime.__send__(op, x.utime),
                           stime.__send__(op, x.stime),
                           cutime.__send__(op, x.cutime),
                           cstime.__send__(op, x.cstime),
                           real.__send__(op, x.real)
                           )
      else
        Benchmark::Tms.new(utime.__send__(op, x),
                           stime.__send__(op, x),
                           cutime.__send__(op, x),
                           cstime.__send__(op, x),
                           real.__send__(op, x)
                           )
      end
    end
  end

  # The default caption string (heading above the output times).
  CAPTION = Benchmark::Tms::CAPTION

  # The default format string used to display times.  See also Benchmark::Tms#format. 
  FMTSTR = Benchmark::Tms::FMTSTR
end

if __FILE__ == $0
  include Benchmark

  n = ARGV[0].to_i.nonzero? || 50000
  puts %Q([#{n} times iterations of `a = "1"'])
  benchmark("       " + CAPTION, 7, FMTSTR) do |x|
    x.report("for:")   {for i in 1..n; a = "1"; end} # Benchmark::measure
    x.report("times:") {n.times do   ; a = "1"; end}
    x.report("upto:")  {1.upto(n) do ; a = "1"; end}
  end

  benchmark do
    [
      measure{for i in 1..n; a = "1"; end},  # Benchmark::measure
      measure{n.times do   ; a = "1"; end},
      measure{1.upto(n) do ; a = "1"; end}
    ]
  end
end
