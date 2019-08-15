require_relative '../../spec_helper'
require_relative 'shared/getgm'

describe "Time#getutc" do
  it_behaves_like :time_getgm, :getutc
end
