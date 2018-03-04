require_relative '../../spec_helper'
require_relative 'shared/month'

describe "Time#mon" do
  it_behaves_like :time_month, :mon
end
