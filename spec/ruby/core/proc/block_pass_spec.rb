require_relative '../../spec_helper'

describe "Proc as a block pass argument" do
  def revivify(&b)
    b
  end

  it "remains the same object if re-vivified by the target method" do
    p = Proc.new {}
    p2 = revivify(&p)
    p.should equal p2
    p.should == p2
  end

  it "remains the same object if reconstructed with Proc.new" do
    p = Proc.new {}
    p2 = Proc.new(&p)
    p.should equal p2
    p.should == p2
  end
end

describe "Proc as an implicit block pass argument" do
  def revivify
    Proc.new
  end

  it "remains the same object if re-vivified by the target method" do
    p = Proc.new {}
    p2 = revivify(&p)
    p.should equal p2
    p.should == p2
  end

  it "remains the same object if reconstructed with Proc.new" do
    p = Proc.new {}
    p2 = Proc.new(&p)
    p.should equal p2
    p.should == p2
  end
end
