require_relative '../../spec_helper'
require_relative 'shared/captures'

describe "MatchData#deconstruct" do
  ruby_version_is "3.2" do
    it_behaves_like :matchdata_captures, :deconstruct
  end
end
