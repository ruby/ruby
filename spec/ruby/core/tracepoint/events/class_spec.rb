require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe 'TracePoint :class event' do
  before do
    ScratchPad.record []
  end

  it 'triggers when a class is defined' do
    TracePoint.new(:class) do |tp|
      next unless TracePointSpec.target_thread?
      ScratchPad.record [tp.event, tp.self, tp.lineno, tp.path]
    end.enable do
      class TracePointSpec::ClassDefined
      end
    end

    ScratchPad.recorded.should == [:class, TracePointSpec::ClassDefined, __LINE__ - 4, __FILE__]
  end

  it 'triggers when a class is defined inside eval' do
    TracePoint.new(:class) do |tp|
      next unless TracePointSpec.target_thread?
      ScratchPad.record tp.self
    end.enable do
      eval <<-RUBY
        class TracePointSpec::ClassDefinedInEval
        end
      RUBY
    end

    ScratchPad.recorded.should == TracePointSpec::ClassDefinedInEval
  end
end
