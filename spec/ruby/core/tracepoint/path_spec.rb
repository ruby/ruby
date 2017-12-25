require File.expand_path('../../../spec_helper', __FILE__)

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
      eval("class A; end")
      path.should == '(eval)'
    end
  end
end
