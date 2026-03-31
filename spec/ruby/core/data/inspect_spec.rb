require_relative '../../spec_helper'
require_relative 'shared/inspect'

describe "Data#inspect" do
  it_behaves_like :data_inspect, :inspect
end
