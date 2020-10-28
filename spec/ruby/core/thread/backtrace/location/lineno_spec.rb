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

  it 'should be the same line number as in #to_s, including for core methods' do
    # Get the caller_locations from a call made into a core library method
    locations = [:non_empty].map { caller_locations }[0]

    locations.each do |location|
      line_number = location.to_s[/:(\d+):/, 1]
      location.lineno.should == Integer(line_number)
    end
  end
end
