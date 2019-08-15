require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/inspect'

describe "Array#inspect" do
  it_behaves_like :array_inspect, :inspect
end
