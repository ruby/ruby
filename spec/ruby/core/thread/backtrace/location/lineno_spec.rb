require_relative '../../../../spec_helper'
require_relative 'fixtures/classes'

describe 'Thread::Backtrace::Location#lineno' do
  before :each do
    @frame = ThreadBacktraceLocationSpecs.locations[0]
    @line  = __LINE__ - 1
  end

  it 'returns the absolute path of the call frame' do
    @frame.lineno.should == @line
  end
end
