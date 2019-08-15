require_relative '../../spec_helper'
require_relative 'shared/asctime'

describe "Time#asctime" do
  it_behaves_like :time_asctime, :asctime
end
