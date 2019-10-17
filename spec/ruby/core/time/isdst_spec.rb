require_relative '../../spec_helper'
require_relative 'shared/isdst'

describe "Time#isdst" do
  it_behaves_like :time_isdst, :isdst
end
