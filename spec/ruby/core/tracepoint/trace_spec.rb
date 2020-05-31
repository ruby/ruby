require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'TracePoint.trace' do
  it 'activates the trace automatically' do
    trace = TracePoint.trace(:line) {}
    trace.should.enabled?
    trace.disable
  end
end
