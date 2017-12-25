require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../fixtures/classes', __FILE__)

describe 'TracePoint#defined_class' do
  it 'returns class or module of the method being called' do
    last_class_name = nil
    TracePoint.new(:call) do |tp|
      last_class_name = tp.defined_class
    end.enable do
      TracePointSpec::B.new.foo
      last_class_name.should equal(TracePointSpec::B)

      TracePointSpec::B.new.bar
      last_class_name.should equal(TracePointSpec::A)

      c = TracePointSpec::C.new
      last_class_name.should equal(TracePointSpec::C)

      c.foo
      last_class_name.should equal(TracePointSpec::B)

      c.bar
      last_class_name.should equal(TracePointSpec::A)
    end
  end
end
