require_relative '../../spec_helper'
require_relative 'shared/day'

describe "Time#mday" do
  it_behaves_like :time_day, :mday
end
