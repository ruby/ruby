require File.expand_path('../../../spec_helper', __FILE__)

describe 'TracePoint#inspect' do
  it 'returns a string containing a human-readable TracePoint status' do
    TracePoint.new(:call) {}.inspect.should ==
      '#<TracePoint:disabled>'
  end
end
