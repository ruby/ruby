require_relative '../../spec_helper'

describe 'TracePoint#lineno' do
  it 'returns the line number of the event' do
    lineno = nil
    TracePoint.new(:line) { |tp| lineno = tp.lineno }.enable do
      lineno.should == 7
    end
  end
end
