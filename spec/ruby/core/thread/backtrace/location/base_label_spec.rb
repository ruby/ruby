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
end
