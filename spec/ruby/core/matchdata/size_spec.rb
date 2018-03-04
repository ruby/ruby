require_relative '../../spec_helper'
require_relative 'shared/length'

describe "MatchData#size" do
  it_behaves_like :matchdata_length, :size
end
