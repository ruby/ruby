require_relative '../../spec_helper'

describe "MatchData.allocate" do
  ruby_version_is "2.7" do
    it "is undefined" do
      # https://bugs.ruby-lang.org/issues/16294
      -> { MatchData.allocate }.should raise_error(NoMethodError)
    end
  end
end
