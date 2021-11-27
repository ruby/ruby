require_relative '../../spec_helper'

describe "Range#inspect" do
  it "provides a printable form, using #inspect to convert the start and end objects" do
    ('A'..'Z').inspect.should == '"A".."Z"'
    ('A'...'Z').inspect.should == '"A"..."Z"'

    (0..21).inspect.should == "0..21"
    (-8..0).inspect.should ==  "-8..0"
    (-411..959).inspect.should == "-411..959"
    (0xfff..0xfffff).inspect.should == "4095..1048575"
    (0.5..2.4).inspect.should == "0.5..2.4"
  end

  it "works for endless ranges" do
    eval("(1..)").inspect.should ==  "1.."
    eval("(0.1...)").inspect.should ==  "0.1..."
  end

  ruby_version_is '2.7' do
    it "works for beginless ranges" do
      eval("(..1)").inspect.should ==  "..1"
      eval("(...0.1)").inspect.should ==  "...0.1"
    end

    it "works for nil ... nil ranges" do
      eval("(..nil)").inspect.should ==  "nil..nil"
      eval("(nil...)").inspect.should ==  "nil...nil"
    end
  end

  ruby_version_is ''...'2.7' do
    it "returns a tainted string if either end is tainted" do
      (("a".taint)..."c").inspect.tainted?.should be_true
      ("a"...("c".taint)).inspect.tainted?.should be_true
      ("a"..."c").taint.inspect.tainted?.should be_true
    end

    it "returns a untrusted string if either end is untrusted" do
      (("a".untrust)..."c").inspect.untrusted?.should be_true
      ("a"...("c".untrust)).inspect.untrusted?.should be_true
      ("a"..."c").untrust.inspect.untrusted?.should be_true
    end
  end
end
