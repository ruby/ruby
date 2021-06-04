require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'TracePoint#binding' do
  def test
    secret = 42
  end

  it 'return the generated binding object from event' do
    bindings = []
    TracePoint.new(:return) { |tp|
      next unless TracePointSpec.target_thread?
      bindings << tp.binding
    }.enable {
      test
    }
    bindings.size.should == 1
    bindings[0].should be_kind_of(Binding)
    bindings[0].local_variables.should == [:secret]
  end
end
