require_relative '../../spec_helper'

describe 'TracePoint.trace' do
  it 'activates the trace automatically' do
    trace = TracePoint.trace(:call) {}
    trace.enabled?.should be_true
    trace.disable
  end
end
