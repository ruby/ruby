require File.expand_path('../../../spec_helper', __FILE__)

describe 'TracePoint#disable' do
  def test; end
  it 'returns true if trace was enabled' do
    event_name, method_name = nil
    trace = TracePoint.new(:call) do |tp|
      event_name = tp.event
      method_name = tp.method_id
    end

    trace.enable
    trace.disable.should be_true
    event_name, method_name = nil
    test
    method_name.equal?(:test).should be_false
    event_name.should equal(nil)
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
    trace.disable { enabled = trace.enabled? }
    enabled.should be_false
    trace.enabled?.should be_true
    trace.disable
  end

  it 'is disabled within a block & also returns false when its called with a block' do
    trace = TracePoint.new(:line) {}
    trace.enable
    trace.disable { trace.enabled? }.should == false
    trace.enabled?.should equal(true)
    trace.disable
  end

  ruby_bug "#14057", "2.0"..."2.5" do
    it 'can accept param within a block but it should not yield arguments' do
      event_name = nil
      trace = TracePoint.new(:line) {}
      trace.enable
      trace.disable do |*args|
        args.should == []
      end
      trace.enabled?.should be_true
      trace.disable
    end
  end
end
