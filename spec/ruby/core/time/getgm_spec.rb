require_relative '../../spec_helper'
require_relative 'shared/getgm'

describe "Time#getgm" do
  it_behaves_like :time_getgm, :getgm
end
