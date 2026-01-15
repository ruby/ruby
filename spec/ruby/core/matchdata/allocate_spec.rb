require_relative '../../spec_helper'

describe "MatchData.allocate" do
  it "is undefined" do
    # https://bugs.ruby-lang.org/issues/16294
    -> { MatchData.allocate }.should raise_error(NoMethodError)
  end
end
