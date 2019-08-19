require_relative '../../spec_helper'

describe "Proc#to_proc" do
  it "returns self" do
    [Proc.new {}, -> {}, proc {}].each { |p|
      p.to_proc.should equal(p)
    }
  end
end
