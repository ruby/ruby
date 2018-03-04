require_relative '../../spec_helper'
require_relative 'shared/to_i'

describe "Time#to_i" do
  it_behaves_like :time_to_i, :to_i
end
