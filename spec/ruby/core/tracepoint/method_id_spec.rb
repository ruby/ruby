require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'TracePoint#method_id' do
  it 'returns the name at the definition of the method being called' do
    method_name = nil
    TracePoint.new(:call) { |tp|
      next unless TracePointSpec.target_thread?
      method_name = tp.method_id
    }.enable do
      TracePointSpec.test
      method_name.should equal(:test)
    end
  end
end
