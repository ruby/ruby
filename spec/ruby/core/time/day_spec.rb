require_relative '../../spec_helper'
require_relative 'shared/day'

describe "Time#day" do
  it_behaves_like :time_day, :day
end
