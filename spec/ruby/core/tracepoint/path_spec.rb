require_relative '../../spec_helper'

describe 'TracePoint#path' do
  it 'returns the path of the file being run' do
    path = nil
    TracePoint.new(:line) { |tp| path = tp.path }.enable do
      path.should == "#{__FILE__}"
    end
  end

  it 'equals (eval) inside an eval for :end event' do
    path = nil
    TracePoint.new(:end) { |tp| path = tp.path }.enable do
      eval("module TracePointSpec; end")
      path.should == '(eval)'
    end
  end
end
