require_relative '../../spec_helper'
require_relative 'shared/inspect'

describe "Set#inspect" do
  it_behaves_like :set_inspect, :inspect
end
