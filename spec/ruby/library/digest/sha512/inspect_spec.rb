require_relative '../../../spec_helper'
require_relative 'shared/constants'

describe "Digest::SHA512#inspect" do

  it "returns a Ruby object representation" do
    cur_digest = Digest::SHA512.new
    cur_digest.inspect.should == "#<#{SHA512Constants::Klass}: #{cur_digest.hexdigest()}>"
  end

end
