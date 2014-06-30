module TracePointChecker
  STATE = {
    count: 0,
    running: false,
  }

  module ZombieTraceHunter
    def before_setup
      @tracepoint_captured_stat = TracePoint.stat.map{|k, (activated, _deleted)| [k, activated]}

      super
    end

    def after_teardown
      super

      # detect zombie traces.
      assert_equal(
        @tracepoint_captured_stat,
        TracePoint.stat.map{|k, (activated, _deleted)| [k, activated]},
        "The number of active trace events was changed"
      )
      # puts "TracePoint - deleted: #{deleted}" if deleted > 0

      TracePointChecker.check if STATE[:running]
    end
  end

  MAIN_THREAD = Thread.current
  TRACES = []

  def self.prefix event
    case event
    when :call, :return
      :n
    when :c_call, :c_return
      :c
    when :b_call, :b_return
      :b
    end
  end

  def self.clear_call_stack
    Thread.current[:call_stack] = []
  end

  def self.call_stack
    stack = Thread.current[:call_stack]
    stack = clear_call_stack unless stack
    stack
  end

  def self.verbose_out label, method
    puts label => call_stack, :count => STATE[:count], :method => method
  end

  def self.method_label tp
    "#{prefix(tp.event)}##{tp.method_id}"
  end

  def self.start verbose: false, stop_at_failure: false
    call_events = %i(a_call)
    return_events = %i(a_return)
    clear_call_stack

    STATE[:running] = true

    TRACES << TracePoint.new(*call_events){|tp|
      next if Thread.current != MAIN_THREAD

      method = method_label(tp)
      call_stack.push method
      STATE[:count] += 1

      verbose_out :psuh, method if verbose
    }

    TRACES << TracePoint.new(*return_events){|tp|
      next if Thread.current != MAIN_THREAD
      STATE[:count] += 1

      method = "#{prefix(tp.event)}##{tp.method_id}"
      verbose_out :pop1, method if verbose

      stored_method = call_stack.pop
      next if stored_method.nil?

      verbose_out :pop2, method if verbose

      if stored_method != method
        stop if stop_at_failure
        RubyVM::SDR() if defined? RubyVM::SDR()
        call_stack.clear
        raise "#{stored_method} is expected, but #{method} (count: #{STATE[:count]})"
      end
    }

    TRACES.each{|trace| trace.enable}
  end

  def self.stop
    STATE[:running] = true
    TRACES.each{|trace| trace.disable}
    TRACES.clear
  end

  def self.check
    TRACES.each{|trace|
      raise "trace #{trace} should not be deactivated" unless trace.enabled?
    }
  end
end

class ::Test::Unit::TestCase
  include TracePointChecker::ZombieTraceHunter
end

# TracePointChecker.start verbose: false
