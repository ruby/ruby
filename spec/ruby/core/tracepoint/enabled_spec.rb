require_relative '../../spec_helper'

describe 'TracePoint#enabled?' do
  it 'returns true when current status of the trace is enable' do
    trace = TracePoint.new(:line) {}
    trace.enable do
      trace.enabled?.should == true
    end
  end

  it 'returns false when current status of the trace is disabled' do
    TracePoint.new(:line) {}.enabled?.should == false
  end
end
