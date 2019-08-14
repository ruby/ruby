require_relative '../../spec_helper'
require_relative 'shared/eql'

describe "MatchData#eql?" do
  it_behaves_like :matchdata_eql, :eql?
end
