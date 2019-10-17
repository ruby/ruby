require_relative '../../spec_helper'
require_relative 'shared/gmt_offset'

describe "Time#utc_offset" do
  it_behaves_like :time_gmt_offset, :utc_offset
end
