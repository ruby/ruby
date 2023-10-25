require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'TracePoint#disable' do
  it 'returns true if trace was enabled' do
    called = false
    trace = TracePoint.new(:line) do |tp|
      next unless TracePointSpec.target_thread?
      called = true
    end

    trace.enable
    begin
      line_event = true
    ensure
      ret = trace.disable
      ret.should == true
    end
    called.should == true

    # Check the TracePoint is disabled
    called = false
    line_event = true
    called.should == false
  end

  it 'returns false if trace was disabled' do
    called = false
    trace = TracePoint.new(:line) do |tp|
      next unless TracePointSpec.target_thread?
      called = true
    end

    line_event = true
    trace.disable.should == false
    line_event = true
    called.should == false
  end

  it 'is disabled within a block & is enabled outside the block' do
    enabled = nil
    trace = TracePoint.new(:line) {}
    trace.enable
    begin
      trace.disable { enabled = trace.enabled? }
      enabled.should == false
      trace.should.enabled?
    ensure
      trace.disable
    end
  end

  it 'returns the return value of the block' do
    trace = TracePoint.new(:line) {}
    trace.enable
    begin
      trace.disable { 42 }.should == 42
      trace.should.enabled?
    ensure
      trace.disable
    end
  end

  it 'can accept param within a block but it should not yield arguments' do
    trace = TracePoint.new(:line) {}
    trace.enable
    begin
      trace.disable do |*args|
        args.should == []
      end
      trace.should.enabled?
    ensure
      trace.disable
    end
  end
end
