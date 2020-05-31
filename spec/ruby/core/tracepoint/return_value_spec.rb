require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'TracePoint#return_value' do
  def test; 'test' end

  it 'returns value from :return event' do
    trace_value = nil
    TracePoint.new(:return) { |tp|
      next unless TracePointSpec.target_thread?
      trace_value = tp.return_value
    }.enable do
      test
      trace_value.should == 'test'
    end
  end
end
