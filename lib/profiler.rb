# Profile provides a way to Profile your Ruby application.
#
# Profiling your program is a way of determining which methods are called and
# how long each method takes to complete.  This way you can detect which
# methods are possible bottlenecks.
#
# Profiling your program will slow down your execution time considerably,
# so activate it only when you need it.  Don't confuse benchmarking with
# profiling.
#
# There are two ways to activate Profiling:
#
# == Command line
#
# Run your Ruby script with <code>-rprofile</code>:
#
#   ruby -rprofile example.rb
#
# If you're profiling an executable in your <code>$PATH</code> you can use
# <code>ruby -S</code>:
#
#   ruby -rprofile -S some_executable
#
# == From code
#
# Just require 'profile':
#
#   require 'profile'
#
#   def slow_method
#     5000.times do
#       9999999999999999*999999999
#     end
#   end
#
#   def fast_method
#     5000.times do
#       9999999999999999+999999999
#     end
#   end
#
#   slow_method
#   fast_method
#
# The output in both cases is a report when the execution is over:
#
#   ruby -rprofile example.rb
#
#     %   cumulative   self              self     total
#    time   seconds   seconds    calls  ms/call  ms/call  name
#    68.42     0.13      0.13        2    65.00    95.00  Integer#times
#    15.79     0.16      0.03     5000     0.01     0.01  Fixnum#*
#    15.79     0.19      0.03     5000     0.01     0.01  Fixnum#+
#     0.00     0.19      0.00        2     0.00     0.00  IO#set_encoding
#     0.00     0.19      0.00        1     0.00   100.00  Object#slow_method
#     0.00     0.19      0.00        2     0.00     0.00  Module#method_added
#     0.00     0.19      0.00        1     0.00    90.00  Object#fast_method
#     0.00     0.19      0.00        1     0.00   190.00  #toplevel

module Profiler__
  class Wrapper < Struct.new(:defined_class, :method_id, :hash) # :nodoc:
    private :defined_class=, :method_id=, :hash=

    def initialize(klass, mid)
      super(klass, mid, nil)
      self.hash = Struct.instance_method(:hash).bind(self).call
    end

    def to_s
      "#{defined_class.inspect}#".sub(/\A\#<Class:(.*)>#\z/, '\1.') << method_id.to_s
    end
    alias inspect to_s
  end

  # internal values
  @@start = nil # the start time that profiling began
  @@stacks = nil # the map of stacks keyed by thread
  @@maps = nil # the map of call data keyed by thread, class and id. Call data contains the call count, total time,
  PROFILE_CALL_PROC = TracePoint.new(*%i[call c_call b_call]) {|tp| # :nodoc:
    now = Process.times[0]
    stack = (@@stacks[Thread.current] ||= [])
    stack.push [now, 0.0]
  }
  PROFILE_RETURN_PROC = TracePoint.new(*%i[return c_return b_return]) {|tp| # :nodoc:
    now = Process.times[0]
    key = Wrapper.new(tp.defined_class, tp.method_id)
    stack = (@@stacks[Thread.current] ||= [])
    if tick = stack.pop
      threadmap = (@@maps[Thread.current] ||= {})
      data = (threadmap[key] ||= [0, 0.0, 0.0, key])
      data[0] += 1
      cost = now - tick[0]
      data[1] += cost
      data[2] += cost - tick[1]
      stack[-1][1] += cost if stack[-1]
    end
  }
module_function
  # Starts the profiler.
  #
  # See Profiler__ for more information.
  def start_profile
    @@start = Process.times[0]
    @@stacks = {}
    @@maps = {}
    PROFILE_CALL_PROC.enable
    PROFILE_RETURN_PROC.enable
  end
  # Stops the profiler.
  #
  # See Profiler__ for more information.
  def stop_profile
    PROFILE_CALL_PROC.disable
    PROFILE_RETURN_PROC.disable
  end
  # Outputs the results from the profiler.
  #
  # See Profiler__ for more information.
  def print_profile(f)
    stop_profile
    total = Process.times[0] - @@start
    if total == 0 then total = 0.01 end
    totals = {}
    @@maps.values.each do |threadmap|
      threadmap.each do |key, data|
        total_data = (totals[key] ||= [0, 0.0, 0.0, key])
        total_data[0] += data[0]
        total_data[1] += data[1]
        total_data[2] += data[2]
      end
    end

    # Maybe we should show a per thread output and a totals view?

    data = totals.values
    data = data.sort_by{|x| -x[2]}
    sum = 0
    f.printf "  %%   cumulative   self              self     total\n"
    f.printf " time   seconds   seconds    calls  ms/call  ms/call  name\n"
    for d in data
      sum += d[2]
      f.printf "%6.2f %8.2f  %8.2f %8d ", d[2]/total*100, sum, d[2], d[0]
      f.printf "%8.2f %8.2f  %s\n", d[2]*1000/d[0], d[1]*1000/d[0], d[3]
    end
    f.printf "%6.2f %8.2f  %8.2f %8d ", 0.0, total, 0.0, 1     # ???
    f.printf "%8.2f %8.2f  %s\n", 0.0, total*1000, "#toplevel" # ???
  end
end
