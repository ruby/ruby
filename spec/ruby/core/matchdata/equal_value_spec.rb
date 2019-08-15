require_relative '../../spec_helper'
require_relative 'shared/eql'

describe "MatchData#==" do
  it_behaves_like :matchdata_eql, :==
end
