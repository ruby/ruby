require_relative '../../spec_helper'

describe "Range#to_s" do
  it "provides a printable form of self" do
    (0..21).to_s.should == "0..21"
    (-8..0).to_s.should ==  "-8..0"
    (-411..959).to_s.should == "-411..959"
    ('A'..'Z').to_s.should == 'A..Z'
    ('A'...'Z').to_s.should == 'A...Z'
    (0xfff..0xfffff).to_s.should == "4095..1048575"
    (0.5..2.4).to_s.should == "0.5..2.4"
  end

  it "can show endless ranges" do
    eval("(1..)").to_s.should == "1.."
    eval("(1.0...)").to_s.should == "1.0..."
  end

  it "can show beginless ranges" do
    (..1).to_s.should == "..1"
    (...1.0).to_s.should == "...1.0"
  end
end
