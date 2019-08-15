require_relative '../../spec_helper'

describe 'TracePoint#return_value' do
  def test; 'test' end

  it 'returns value from :return event' do
    trace_value = nil
    TracePoint.new(:return) { |tp| trace_value = tp.return_value}.enable do
      test
      trace_value.should == 'test'
    end
  end
end
