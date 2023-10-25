require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/inspect'

describe "Struct#inspect" do
  it_behaves_like :struct_inspect, :inspect
end
