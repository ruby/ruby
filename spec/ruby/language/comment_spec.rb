require_relative '../spec_helper'

describe "The comment" do
  it "can be placed between fluent dot now" do
    code = <<~CODE
      10
        # some comment
        .to_s
      CODE

    eval(code).should == '10'
  end
end
