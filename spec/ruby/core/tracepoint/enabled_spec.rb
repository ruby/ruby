require File.expand_path('../../../spec_helper', __FILE__)

describe 'TracePoint#enabled?' do
  it 'returns true when current status of the trace is enable' do
    trace = TracePoint.new(:call) {}
    trace.enable do
      trace.enabled?.should be_true
    end
  end

  it 'returns false when current status of the trace is disabled' do
    TracePoint.new(:call) {}.enabled?.should be_false
  end
end
