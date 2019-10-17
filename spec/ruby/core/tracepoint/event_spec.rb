require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'TracePoint#event' do
  it 'returns the type of event' do
    event_name = nil
    TracePoint.new(:end, :call) do |tp|
      event_name = tp.event
    end.enable do
      TracePointSpec.test
      event_name.should equal(:call)

      TracePointSpec::B.new.foo
      event_name.should equal(:call)

      class TracePointSpec::B; end
      event_name.should equal(:end)
    end

  end
end
