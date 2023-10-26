require_relative '../../spec_helper'
require_relative 'shared/captures'

describe "MatchData#captures" do
  it_behaves_like :matchdata_captures, :captures
end
