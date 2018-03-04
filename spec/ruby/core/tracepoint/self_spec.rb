require_relative '../../spec_helper'

describe 'TracePoint#self' do
  it 'return the trace object from event' do
    trace = nil
    TracePoint.new(:line) { |tp| trace = tp.self }.enable do
      trace.equal?(self).should be_true
    end
  end
end
