require_relative '../../../../spec_helper'
require_relative 'fixtures/classes'

describe 'Thread::Backtrace::Location#inspect' do
  before :each do
    @frame = ThreadBacktraceLocationSpecs.locations[0]
    @line  = __LINE__ - 1
  end

  it 'converts the call frame to a String' do
    @frame.inspect.should include("#{__FILE__}:#{@line}:in ")
  end
end
