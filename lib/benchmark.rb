#
# benchmark.rb
#
=begin
= benchmark.rb

== NAME
((*benchmark.rb*)) - a benchmark utility

== SYNOPSIS
  ----------
       require "benchmark"
       include Benchmark
  ----------

== DESCRIPTION 

benchmark.rb provides some utilities to measure and report the
times used and passed to execute.  

== SIMPLE EXAMPLE

=== EXAMPLE 0
To ((<measure>)) the times to make (({"a"*1_000_000})):

  ----------
       puts measure{ "a"*1_000_000 }
  ----------

On my machine (FreeBSD 3.2 on P5100MHz) this reported as follows:

  ----------
         1.166667   0.050000   1.216667 (  0.571355)
  ----------

The above shows user time, system time, user+system, and really passed
time.  The unit of time is second.

=== EXAMPLE 1
To do some experiments sequentially, ((<bm>)) is useful:

  ----------
       n = 50000
       bm do |x|
         x.report{for i in 1..n; a = "1"; end}
         x.report{n.times do   ; a = "1"; end}
         x.report{1.upto(n) do ; a = "1"; end}
       end
  ----------

The result:
  ----------
             user     system      total        real
         1.033333   0.016667   1.016667 (  0.492106)
         1.483333   0.000000   1.483333 (  0.694605)
         1.516667   0.000000   1.516667 (  0.711077)
  ----------

=== EXAMPLE 2
To put a label in each ((<report>)):

  ----------
       n = 50000
       bm(7) do |x|
         x.report("for:")   {for i in 1..n; a = "1"; end}
         x.report("times:") {n.times do   ; a = "1"; end}
         x.report("upto:")  {1.upto(n) do ; a = "1"; end}
       end
  ----------

The option (({7})) specifies the offset of each report accoding to the
longest label.

This reports as follows:

  ----------
                    user     system      total        real
       for:     1.050000   0.000000   1.050000 (  0.503462)
       times:   1.533333   0.016667   1.550000 (  0.735473)
       upto:    1.500000   0.016667   1.516667 (  0.711239)
  ----------

=== EXAMPLE 3

By the way, benchmarks might seem to depend on the order of items.  It
is caused by the cost of memory allocation and the garbage collection.
To prevent this boresome, Benchmark::((<bmbm>)) is provided, e.g., to
compare ways for sort array of strings:

  ----------
       require "rbconfig"
       include Config
       def file
         open("%s/lib/ruby/%s.%s/tk.rb" % 
              [CONFIG['prefix'],CONFIG['MAJOR'],CONFIG['MINOR']]).read
       end

       n = 10
       bmbm do |x|
         x.report("destructive!"){ 
           t = (file*n).to_a; t.each{|line| line.upcase!}; t.sort!
         }
         x.report("method chain"){ 
           t = (file*n).to_a.collect{|line| line.upcase}.sort
         }
       end
  ----------

This reports:

  ----------
       Rehearsal ------------------------------------------------
       destructive!   2.664062   0.070312   2.734375 (  2.783401)
       method chain   5.257812   0.156250   5.414062 (  5.736088)
       --------------------------------------- total: 8.148438sec
       
                          user     system      total        real
       destructive!   2.359375   0.007812   2.367188 (  2.381015)
       method chain   3.046875   0.023438   3.070312 (  3.085816)
  ----------

=== EXAMPLE 4
To report statistics of sequential experiments with unique label,
((<benchmark>)) is available:

  ----------
       n = 50000
       benchmark(" "*7 + CAPTION, 7, FMTSTR, ">total:", ">avg:") do |x|
         tf = x.report("for:")  {for i in 1..n; a = "1"; end}
         tt = x.report("times:"){n.times do   ; a = "1"; end}
         tu = x.report("upto:") {1.upto(n) do ; a = "1"; end}
         [tf+tt+tu, (tf+tt+tu)/3]
       end
  ----------

The result:

  ----------
                    user     system      total        real
       for:     1.016667   0.016667   1.033333 (  0.485749)
       times:   1.450000   0.016667   1.466667 (  0.681367)
       upto:    1.533333   0.000000   1.533333 (  0.722166)
       >total:  4.000000   0.033333   4.033333 (  1.889282)
       >avg:    1.333333   0.011111   1.344444 (  0.629761)
  ----------

== Benchmark module

=== CONSTANT
:CAPTION
  CAPTION is a caption string which is used in Benchmark::((<benchmark>)) and 
  Benchmark::Report#((<report>)). 
:FMTSTR
  FMTSTR is a format string which is used in Benchmark::((<benchmark>)) and 
  Benchmark::Report#((<report>)). See also Benchmark::Tms#((<format>)). 
:BENCHMARK_VERSION
  BENCHMARK_VERSION is version string which statnds for the last modification
  date (YYYY-MM-DD). 

=== INNER CLASS
* ((<Benchmark::Job>))
* ((<Benchmark::Report>))
* ((<Benchmark::Tms>))

=== MODULE FUNCTION
==== benchmark
  ----------
       benchmark([caption [, label_width [, fmtstr]]]) do |x| ... end
       benchmark([caption [, label_width [, fmtstr]]]) do array_of_Tms end
       benchmark([caption [, label_width [, fmtstr [, labels...]]]]) do 
         ...
         array_of_Tms
       end
  ----------

(({benchmark})) reports the times. In the first form the block variable x is
treated as a ((<Benchmark::Report>)) object, which has ((<report>)) method.
In the second form, each member of array_of_Tms is reported in the
specified form if the member is a ((<Benchmark::Tms>)) object.  The
last form provides combined above two forms (See ((<EXAMPLE 3>))). 

The following lists the meaning of each option. 

:caption
 A string ((|caption|)) is printed once before execution of the given block. 

:label_width
 An integer ((|label_width|)) is used as an offset in each report. 

:fmtstr
 An string ((|fmtstr|)) is used to format each measurement. 
 See ((<format>))

:labels
 The rest parameters labels is used as prefix of the format to the
 value of block, that is array_of_Tms.

==== bm
  ----------
       bm([label_width [, labels ...]) do ... end
  ----------

(({bm})) is a simpler interface of ((<benchmark>)). 
(({bm})) acts as same as follows:

  benchmark(" "*label_width + CAPTION, label_width, FMTSTR, *labels) do 
    ... 
  end

==== bmbm
  ----------
       bmbm([label_width]) do |x|
         x.item("label1") { .... } 
         ....
       end
  ----------

(({bmbm})) is yet another ((<benchmark>)).  This utility function is
provited to prevent a kind of job order dependency, which is caused
by memory allocation and object creation.  The usage is similar to
((<bm>)) but has less options and does extra three things:

  (1) ((*Rehearsal*)): runs all items in the job ((<list>)) to allocate
      enough memory.
  (2) ((*GC*)): before each ((<measure>))ment, invokes (({GC.start})) to
      prevent the influence of previous job. 
  (3) If given ((|label_width|)) is less than the maximal width of labels
      given as ((|item|))'s argument, the latter is used.  
      Because (({bmbm})) is a 2-pass procedure, this is possible. 

(({bmbm})) returns an array which consists of Tms correspoding to each
(({item})). 
==== measure 
  ----------
       measure([label]) do ... end
  ----------

measure returns the times used and passed to execute the given block as a
Benchmark::Tms object. 

==== realtime
  ----------
       realtime do ... end
  ----------

realtime returns the times passed to execute the given block. 

== Benchmark::Report

=== CLASS METHOD

==== Benchmark::Report::new(width)
  ----------
       Benchmark::Report::new([width [, fmtstr]])
  ----------

Usually, one doesn't have to use this method directly, 
(({Benchmark::Report::new})) is called by ((<benchmark>)) or ((<bm>)). 
((|width|)) and ((|fmtstr|)) are the offset of ((|label|)) and 
format string responsively; Both of them are used in ((<format>)). 

=== METHOD

==== report

  ----------
       report(fmt, *args)
  ----------

This method reports label and time formated by ((|fmt|)).  See
((<format>)) of Benchmark::Tms for formatting rule.

== Benchmark::Tms

=== CLASS METHOD

== Benchmark::Job

=== CLASS METHOD

==== Benchmark::Job::new
  ----------
       Benchmark::Job::new(width)
  ----------

Usually, one doesn't have to use this method directly,
(({Benchmark::Job::new})) is called by ((<bmbm>)). 
((|width|)) is a initial value for the offset ((|label|)) for formatting. 
((<bmbm>)) passes its argument ((|width|)) to this constructor. 

=== METHOD

==== item
  ----------
       item(((|lable|))){ .... }
  ----------

(({item})) registers a pair of (((|label|))) and given block as job ((<list>)). 
==== width

Maximum length of labels in ((<list>)) plus one.  

==== list

array of array which consists of label and jop proc. 

==== report

alias to ((<item>)).

==== Benchmark::Tms::new
  ----------
       Benchmark::Tms::new([u [, s [, cu [, cs [, re [, l]]]]]])
  ----------

returns new Benchmark::Tms object which has
((|u|))  as ((<utime>)), 
((|s|))  as ((<stime>)), 
((|cu|)) as ((<cutime>))
((|cs|)) as ((<cstime>)), 
((|re|)) as ((<real>)) and
((|l|))  as ((<label>)). 

The default value is assumed as 0.0 for ((|u|)), ((|s|)), ((|cu|)),
((|cs|)) and ((|re|)). The default of ((|l|)) is null string ((({""}))). 

==== operator +
  ----------
       tms1 + tms2
  ----------

returns a new Benchmark::Tms object as memberwise summation. 
This method and ((<(('operator /'))>)) is useful to take statistics. 

==== operator /
  ----------
       tms / num
  ----------

returns a new Benchmark::Tms object as memberwise division by ((|num|)). 
This method and ((<operator +>)) is useful to take statistics. 

==== add
  ----------
       add do ... end
  ----------

returns a new Benchmark::Tms object which is the result of additional
execution which is given by block. 

==== add!
  ----------
       add! do ... end
  ----------

do additional execution which is given by block. 

==== format
  ----------
       format([fmtstr [, *args]])
  ----------

(({format})) returns formatted string of (({self})) according to a
((|fmtstr|)) like (({Kernel::format})). In addition, (({format})) accepts
some extentions as follows:
  :%u
    ((<utime>)).
  :%y
    ((<stime>)). (Mnemonic: y of ``s((*y*))stem'')
  :%U
    ((<cutime>)). 
  :%Y
    ((<cstime>)). 
  :%t
    ((<total>)). 
  :%r
    ((<real>)). 
  :%n
    ((<label>)). (Mnemonic: n of ``((*n*))ame'')

If fmtstr is not given ((<FMTSTR>)) is used as default value. 

==== utime

returns user time. 

==== stime

returns system time. 

==== cutime

returns user time of children. 

==== cstime

returns system time of children. 

==== total

returns total time, that is 
((<utime>)) + ((<stime>)) + ((<cutime>)) + ((<cstime>)). 

==== real

returns really passed time. 

==== label

returns label. 

==== to_a

returns a new array as follows

  [label, utime, stime, cutime, cstime, real]

==== to_s

same as (({format()})). See also ((<format>)).

== HISTORY

A benchmark.rb appeared in RAA January 1st 2000. 

== AUTHOR

Gotoken (gotoken@notwork.org). 
=end

module Benchmark
  BENCHMARK_VERSION = "2002-04-25"

  def Benchmark::times()
      Process::times()
  end

  def benchmark(caption = "", label_width = nil, fmtstr = nil, *labels)
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

  def bm(label_width = 0, *labels, &blk)
    benchmark(" "*label_width + CAPTION, label_width, FMTSTR, *labels, &blk)
  end

  def bmbm(width = 0, &blk)
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

  def measure(label = "")
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

  def realtime(&blk)
    Benchmark::measure(&blk).real
  end

  class Job
    def initialize(width)
      @width = width
      @list = []
    end

    def item(label = "", &blk)
      raise ArgmentError, "no block" unless block_given?
      label.concat ' '
      w = label.length
      @width = w if @width < w
      @list.push [label, blk]
      self
    end

    alias report item
    attr_reader :list, :width
  end

  module_function :benchmark, :measure, :realtime, :bm, :bmbm

  class Report
    def initialize(width = 0, fmtstr = nil)
      @width, @fmtstr = width, fmtstr
    end

    def item(label = "", *fmt, &blk)
      print label.ljust(@width)
      res = Benchmark::measure(&blk)
      print res.format(@fmtstr, *fmt)
      res
    end

    alias report item
  end

  class Tms
    CAPTION = "      user     system      total        real\n"
    FMTSTR = "%10.6u %10.6y %10.6t %10.6r\n"

    attr_reader :utime, :stime, :cutime, :cstime, :real, :total, :label

    def initialize(u = 0.0, s = 0.0, cu = 0.0, cs = 0.0, real = 0.0, l = nil)
      @utime, @stime, @cutime, @cstime, @real, @label = u, s, cu, cs, real, l
      @total = @utime + @stime + @cutime + @cstime
    end

    def add(&blk)
      self + Benchmark::measure(&blk) 
    end

    def add!
      t = Benchmark::measure(&blk) 
      @utime  = utime + t.utime
      @stime  = stime + t.stime
      @cutime = cutime + t.cutime
      @cstime = cstime + t.cstime
      @real   = real + t.real
      self
    end

    def +(x); memberwise(:+, x) end
    def -(x); memberwise(:-, x) end
    def *(x); memberwise(:*, x) end
    def /(x); memberwise(:/, x) end

    def format(arg0 = nil, *args)
      fmtstr = (arg0 || FMTSTR).dup
      fmtstr.gsub!(/(%[\-+\.\d]*)n/){"#{$1}s" % label}
      fmtstr.gsub!(/(%[\-+\.\d]*)u/){"#{$1}f" % utime}
      fmtstr.gsub!(/(%[\-+\.\d]*)y/){"#{$1}f" % stime}
      fmtstr.gsub!(/(%[\-+\.\d]*)U/){"#{$1}f" % cutime}
      fmtstr.gsub!(/(%[\-+\.\d]*)Y/){"#{$1}f" % cstime}
      fmtstr.gsub!(/(%[\-+\.\d]*)t/){"#{$1}f" % total}
      fmtstr.gsub!(/(%[\-+\.\d]*)r/){"(#{$1}f)" % real}
      arg0 ? Kernel::format(fmtstr, *args) : fmtstr
    end

    def to_s
      format
    end

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

  CAPTION = Benchmark::Tms::CAPTION
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
