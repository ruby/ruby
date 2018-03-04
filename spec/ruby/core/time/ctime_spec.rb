require_relative '../../spec_helper'
require_relative 'shared/asctime'

describe "Time#ctime" do
  it_behaves_like :time_asctime, :ctime
end
