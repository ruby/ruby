require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/to_s'
require_relative '../method/shared/aliased_inspect'

describe "UnboundMethod#inspect" do
  it_behaves_like :unboundmethod_to_s, :inspect
  it_behaves_like :method_to_s_aliased, :inspect, -> meth { meth.unbind }
end
