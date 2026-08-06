require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'TracePoint.trace' do
  it 'activates the trace automatically' do
    trace = TracePoint.trace(:line) {}
    trace.should.enabled?
    trace.disable
  end

  it 'clears $! when invoking the trace block' do
    exception_in_trace = nil
    trace = TracePoint.trace(:raise) do |tp|
      exception_in_trace = $!
    end
    begin
      raise
    rescue => e
      exception_in_trace.should == nil
      $!.should == e
    end
    trace.disable
  end
end
