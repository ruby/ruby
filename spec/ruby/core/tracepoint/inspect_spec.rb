require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'TracePoint#inspect' do
  before do
    @path_prefix = ' '
  end

  it 'returns a string containing a human-readable TracePoint status' do
    TracePoint.new(:line) {}.inspect.should == '#<TracePoint:disabled>'
  end

  it "shows only whether it's enabled when outside the TracePoint handler" do
    trace = TracePoint.new(:line) {}
    trace.enable

    trace.inspect.should == '#<TracePoint:enabled>'

    trace.disable
  end

  it 'returns a String showing the event, path and line' do
    inspect = nil
    line = nil
    TracePoint.new(:line) { |tp|
      next unless TracePointSpec.target_thread?
      next unless tp.path == __FILE__

      inspect ||= tp.inspect
    }.enable do
      line = __LINE__
    end

    inspect.should == "#<TracePoint:line#{@path_prefix}#{__FILE__}:#{line}>"
  end

  it 'returns a String showing the event, method, path and line for a :call event' do
    inspect = nil
    line = nil
    TracePoint.new(:call) { |tp|
      next unless TracePointSpec.target_thread?
      next unless tp.path == __FILE__

      inspect ||= tp.inspect
    }.enable do
      line = __LINE__ + 1
      def trace_point_spec_test_call; end
      trace_point_spec_test_call
    end

    inspect.should =~ /\A#<TracePoint:call [`']trace_point_spec_test_call'#{@path_prefix}#{__FILE__}:#{line}>\z/
  end

  it 'returns a String showing the event, method, path and line for a :return event' do
    inspect = nil
    line = nil
    TracePoint.new(:return) { |tp|
      next unless TracePointSpec.target_thread?
      next unless tp.path == __FILE__

      inspect ||= tp.inspect
    }.enable do
      line = __LINE__ + 4
      def trace_point_spec_test_return
        a = 1
        return a
      end
      trace_point_spec_test_return
    end
    ruby_version_is("3.4") { line = "(?:#{line}|#{line-1})" }

    inspect.should =~ /\A#<TracePoint:return [`']trace_point_spec_test_return'#{@path_prefix}#{__FILE__}:#{line}>\z/
  end

  it 'returns a String showing the event, method, path and line for a :c_call event' do
    inspect = nil
    tracepoint = TracePoint.new(:c_call) { |tp|
      next unless TracePointSpec.target_thread?
      next unless tp.path == __FILE__

      inspect ||= tp.inspect
    }
    line = __LINE__ + 2
    tracepoint.enable do
      [0, 1].max
    end

    inspect.should =~ /\A#<TracePoint:c_call [`']max'#{@path_prefix}#{__FILE__}:#{line}>\z/
  end

  it 'returns a String showing the event, path and line for a :class event' do
    inspect = nil
    line = nil
    TracePoint.new(:class) { |tp|
      next unless TracePointSpec.target_thread?
      next unless tp.path == __FILE__

      inspect ||= tp.inspect
    }.enable do
      line = __LINE__ + 1
      class TracePointSpec::C
      end
    end

    inspect.should == "#<TracePoint:class#{@path_prefix}#{__FILE__}:#{line}>"
  end

  it 'returns a String showing the event and thread for :thread_begin event' do
    inspect = nil
    thread = nil
    thread_inspection = nil
    TracePoint.new(:thread_begin) { |tp|
      next unless Thread.current == thread

      inspect ||= tp.inspect
    }.enable(target_thread: nil) do
      thread = Thread.new {}
      thread_inspection = thread.inspect
      thread.join
    end

    inspect.should == "#<TracePoint:thread_begin #{thread_inspection}>"
  end

  it 'returns a String showing the event and thread for :thread_end event' do
    inspect = nil
    thread = nil
    thread_inspection = nil
    TracePoint.new(:thread_end) { |tp|
      next unless Thread.current == thread

      inspect ||= tp.inspect
    }.enable(target_thread: nil) do
      thread = Thread.new {}
      thread_inspection = thread.inspect
      thread.join
    end

    inspect.should == "#<TracePoint:thread_end #{thread_inspection}>"
  end
end
