require File.expand_path('../../../spec_helper', __FILE__)

describe 'TracePoint.trace' do
  it 'activates the trace automatically' do
    trace = TracePoint.trace(:call) {}
    trace.enabled?.should be_true
    trace.disable
  end
end
