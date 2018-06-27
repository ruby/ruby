require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::SHA256#inspect" do

  it "returns a Ruby object representation" do
    cur_digest = Digest::SHA256.new
    cur_digest.inspect.should == "#<#{SHA256Constants::Klass}: #{cur_digest.hexdigest()}>"
  end

end
