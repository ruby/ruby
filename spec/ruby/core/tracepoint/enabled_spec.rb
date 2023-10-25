require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'TracePoint#enabled?' do
  it 'returns true when current status of the trace is enable' do
    trace = TracePoint.new(:line) {}
    trace.enable do
      trace.should.enabled?
    end
  end

  it 'returns false when current status of the trace is disabled' do
    TracePoint.new(:line) {}.should_not.enabled?
  end
end
