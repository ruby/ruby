require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'TracePoint#inspect' do
  it 'returns a string containing a human-readable TracePoint status' do
    TracePoint.new(:line) {}.inspect.should == '#<TracePoint:disabled>'
  end

  it 'returns a String showing the event, path and line' do
    inspect = nil
    line = nil
    TracePoint.new(:line) { |tp|
      next unless TracePointSpec.target_thread?
      inspect ||= tp.inspect
    }.enable do
      line = __LINE__
    end

    inspect.should == "#<TracePoint:line@#{__FILE__}:#{line}>"
  end

  it 'returns a String showing the event, path and line for a :class event' do
    inspect = nil
    line = nil
    TracePoint.new(:class) { |tp|
      next unless TracePointSpec.target_thread?
      inspect ||= tp.inspect
    }.enable do
      line = __LINE__ + 1
      class TracePointSpec::C
      end
    end

    inspect.should == "#<TracePoint:class@#{__FILE__}:#{line}>"
  end
end
