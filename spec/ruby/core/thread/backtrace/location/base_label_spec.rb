require_relative '../../../../spec_helper'
require_relative 'fixtures/classes'

describe 'Thread::Backtrace::Location#base_label' do
  before :each do
    @frame = ThreadBacktraceLocationSpecs.locations[0]
  end

  it 'returns the base label of the call frame' do
    @frame.base_label.should == '<top (required)>'
  end

  describe 'when call frame is inside a block' do
    before :each do
      @frame = ThreadBacktraceLocationSpecs.block_location[0]
    end

    it 'returns the name of the method that contains the block' do
      @frame.base_label.should == 'block_location'
    end
  end

  it "is <module:A> for a module body" do
    module ThreadBacktraceLocationSpecs
      module ModuleLabel
        ScratchPad.record caller_locations(0, 1)[0].base_label
      end
    end
    ScratchPad.recorded.should == '<module:ModuleLabel>'
  end

  it "is <class:A> for a class body" do
    module ThreadBacktraceLocationSpecs
      class ClassLabel
        ScratchPad.record caller_locations(0, 1)[0].base_label
      end
    end
    ScratchPad.recorded.should == '<class:ClassLabel>'
  end

  it "is 'singleton class' for a singleton class body" do
    module ThreadBacktraceLocationSpecs
      class << Object.new
        ScratchPad.record caller_locations(0, 1)[0].base_label
      end
    end
    ScratchPad.recorded.should =~ /\A(singleton class|<singleton class>)\z/
  end
end
