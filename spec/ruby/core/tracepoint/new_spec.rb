require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'TracePoint.new' do
  it 'returns a new TracePoint object, not enabled by default' do
    TracePoint.new(:line) {}.enabled?.should be_false
  end

  it 'includes :line event when event is not specified' do
    event_name = nil
    TracePoint.new { |tp|
      next unless TracePointSpec.target_thread?
      event_name = tp.event
    }.enable do
      event_name.should equal(:line)

      event_name = nil
      TracePointSpec.test
      event_name.should equal(:line)

      event_name = nil
      TracePointSpec::B.new.foo
      event_name.should equal(:line)
    end
  end

  it 'converts given event name as string into symbol using to_sym' do
    event_name = nil
    (o = mock('line')).should_receive(:to_sym).and_return(:line)

    TracePoint.new(o) { |tp|
      next unless TracePointSpec.target_thread?
      event_name = tp.event
    }.enable do
      line_event = true
      event_name.should == :line
    end
  end

  it 'includes multiple events when multiple event names are passed as params' do
    event_name = nil
    TracePoint.new(:end, :call) do |tp|
      next unless TracePointSpec.target_thread?
      event_name = tp.event
    end.enable do
      TracePointSpec.test
      event_name.should equal(:call)

      TracePointSpec::B.new.foo
      event_name.should equal(:call)

      class TracePointSpec::B; end
      event_name.should equal(:end)
    end
  end

  it 'raises a TypeError when the given object is not a string/symbol' do
    o = mock('123')
    -> { TracePoint.new(o) {} }.should raise_error(TypeError)

    o.should_receive(:to_sym).and_return(123)
    -> { TracePoint.new(o) {} }.should raise_error(TypeError)
  end

  it 'expects to be called with a block' do
    -> { TracePoint.new(:line) }.should raise_error(ArgumentError, "must be called with a block")
  end

  it "raises a Argument error when the given argument doesn't match an event name" do
    -> { TracePoint.new(:test) }.should raise_error(ArgumentError, "unknown event: test")
  end
end
