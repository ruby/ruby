require_relative '../../spec_helper'
require_relative 'shared/month'

describe "Time#month" do
  it_behaves_like :time_month, :month
end
