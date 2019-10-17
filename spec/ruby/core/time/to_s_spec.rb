require_relative '../../spec_helper'
require_relative 'shared/inspect'

describe "Time#to_s" do
  it_behaves_like :inspect, :to_s
end
