require_relative '../../../../spec_helper'
require_relative 'fixtures/classes'

describe 'Thread::Backtrace::Location#absolute_path' do
  before :each do
    @frame = ThreadBacktraceLocationSpecs.locations[0]
  end

  it 'returns the absolute path of the call frame' do
    @frame.absolute_path.should == File.realpath(__FILE__)
  end
end
