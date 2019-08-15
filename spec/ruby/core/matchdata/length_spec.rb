require_relative '../../spec_helper'
require_relative 'shared/length'

describe "MatchData#length" do
  it_behaves_like :matchdata_length, :length
end
