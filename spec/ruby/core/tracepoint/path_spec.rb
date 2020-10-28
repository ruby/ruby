require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'TracePoint#path' do
  it 'returns the path of the file being run' do
    path = nil
    TracePoint.new(:line) { |tp|
      next unless TracePointSpec.target_thread?
      path = tp.path
    }.enable do
      line_event = true
    end
    path.should == "#{__FILE__}"
  end

  it 'equals (eval) inside an eval for :end event' do
    path = nil
    TracePoint.new(:end) { |tp|
      next unless TracePointSpec.target_thread?
      path = tp.path
    }.enable do
      eval("module TracePointSpec; end")
    end
    path.should == '(eval)'
  end
end
