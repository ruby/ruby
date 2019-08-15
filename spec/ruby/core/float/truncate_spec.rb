require_relative '../../spec_helper'
require_relative 'shared/to_i'

describe "Float#truncate" do
  it_behaves_like :float_to_i, :truncate

  it "returns self truncated to an optionally given precision" do
    2.1679.truncate(0).should   eql(2)
    7.1.truncate(1).should      eql(7.1)
    214.94.truncate(-1).should  eql(210)
    -1.234.truncate(2).should   eql(-1.23)
    5.123812.truncate(4).should eql(5.1238)
  end
end
