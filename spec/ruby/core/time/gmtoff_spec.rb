require_relative '../../spec_helper'
require_relative 'shared/gmt_offset'

describe "Time#gmtoff" do
  it_behaves_like :time_gmt_offset, :gmtoff
end
