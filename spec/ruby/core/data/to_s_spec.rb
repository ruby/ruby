require_relative '../../spec_helper'
require_relative 'shared/inspect'

describe "Data#to_s" do
  it_behaves_like :data_inspect, :to_s
end
