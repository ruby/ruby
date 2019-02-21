require_relative '../../spec_helper'

describe 'TracePoint.trace' do
  it 'activates the trace automatically' do
    trace = TracePoint.trace(:line) {}
    trace.enabled?.should == true
    trace.disable
  end
end
