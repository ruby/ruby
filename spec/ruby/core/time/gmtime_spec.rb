require_relative '../../spec_helper'
require_relative 'shared/gmtime'

describe "Time#gmtime" do
  it_behaves_like :time_gmtime, :gmtime
end
