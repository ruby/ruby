require_relative '../../spec_helper'

describe 'TracePoint#disable' do
  def test; end
  it 'returns true if trace was enabled' do
    called = false
    trace = TracePoint.new(:call) do |tp|
      called = true
    end

    trace.enable
    trace.disable.should be_true

    # Check the TracePoint is disabled
    called = false
    test
    called.should == false
  end

  it 'returns false if trace was disabled' do
    event_name, method_name = nil
    trace = TracePoint.new(:call) do |tp|
      event_name = tp.event
      method_name = tp.method_id
    end

    trace.disable.should be_false
    event_name, method_name = nil
    test
    method_name.equal?(:test).should be_false
    event_name.should equal(nil)
  end

  it 'is disabled within a block & is enabled outside the block' do
    enabled = nil
    trace = TracePoint.new(:line) {}
    trace.enable
    begin
      trace.disable { enabled = trace.enabled? }
      enabled.should be_false
      trace.enabled?.should be_true
    ensure
      trace.disable
    end
  end

  it 'is disabled within a block & also returns false when its called with a block' do
    trace = TracePoint.new(:line) {}
    trace.enable
    begin
      trace.disable { trace.enabled? }.should == false
      trace.enabled?.should equal(true)
    ensure
      trace.disable
    end
  end

  ruby_bug "#14057", ""..."2.5" do
    it 'can accept param within a block but it should not yield arguments' do
      event_name = nil
      trace = TracePoint.new(:line) {}
      trace.enable
      begin
        trace.disable do |*args|
          args.should == []
        end
        trace.enabled?.should be_true
      ensure
        trace.disable
      end
    end
  end
end
