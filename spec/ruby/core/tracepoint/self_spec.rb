require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'TracePoint#self' do
  it 'return the trace object from event' do
    trace = nil
    TracePoint.new(:line) { |tp| trace = tp.self }.enable do
      trace.equal?(self).should be_true
    end
  end

  it 'return the class object from a class event' do
    trace = nil
    TracePoint.new(:class) { |tp| trace = tp.self }.enable do
      class TracePointSpec::C
      end
    end
    trace.should equal TracePointSpec::C
  end
end
