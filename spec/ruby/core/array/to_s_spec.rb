require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/join'
require_relative 'shared/inspect'

describe "Array#to_s" do
  it_behaves_like :array_inspect, :to_s
end
