require_relative '../../spec_helper'
require_relative 'shared/to_i'

describe "Time#tv_sec" do
  it_behaves_like :time_to_i, :tv_sec
end
