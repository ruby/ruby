require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/to_s'

describe "UnboundMethod#inspect" do
  it_behaves_like :unboundmethod_to_s, :inspect
end
