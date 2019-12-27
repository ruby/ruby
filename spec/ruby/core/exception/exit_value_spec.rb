require_relative '../../spec_helper'

describe "LocalJumpError#exit_value" do
  def get_me_a_return
    Proc.new { return 42 }
  end

  it "returns the value given to return" do
    -> { get_me_a_return.call }.should raise_error(LocalJumpError) { |e|
      e.exit_value.should == 42
    }
  end
end
