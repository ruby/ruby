require_relative '../../spec_helper'
require_relative 'shared/captures'

describe "MatchData#deconstruct" do
  it_behaves_like :matchdata_captures, :deconstruct
end
