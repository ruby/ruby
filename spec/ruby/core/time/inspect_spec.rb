require_relative '../../spec_helper'
require_relative 'shared/inspect'

describe "Time#inspect" do
  it_behaves_like :inspect, :inspect
end
