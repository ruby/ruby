require_relative '../../spec_helper'

ruby_version_is '3.3' do
  describe "Range#overlap?" do
    it "returns true if other Range overlaps self" do
      (0..2).overlap?(1..3).should == true
      (1..3).overlap?(0..2).should == true
      (0..2).overlap?(0..2).should == true
      (0..3).overlap?(1..2).should == true
      (1..2).overlap?(0..3).should == true

      ('a'..'c').overlap?('b'..'d').should == true
    end

    it "returns false if other Range does not overlap self" do
      (0..2).overlap?(3..4).should == false
      (0..2).overlap?(-4..-1).should == false

      ('a'..'c').overlap?('d'..'f').should == false
    end

    it "raises TypeError when called with non-Range argument" do
      -> {
        (0..2).overlap?(1)
      }.should raise_error(TypeError, "wrong argument type Integer (expected Range)")
    end

    it "returns true when beginningless and endless Ranges overlap" do
      (0..2).overlap?(..3).should == true
      (0..2).overlap?(..1).should == true
      (0..2).overlap?(..0).should == true

      (..3).overlap?(0..2).should == true
      (..1).overlap?(0..2).should == true
      (..0).overlap?(0..2).should == true

      (0..2).overlap?(-1..).should == true
      (0..2).overlap?(1..).should == true
      (0..2).overlap?(2..).should == true

      (-1..).overlap?(0..2).should == true
      (1..).overlap?(0..2).should == true
      (2..).overlap?(0..2).should == true

      (0..).overlap?(2..).should == true
      (..0).overlap?(..2).should == true
    end

    it "returns false when beginningless and endless Ranges do not overlap" do
      (0..2).overlap?(..-1).should == false
      (0..2).overlap?(3..).should == false

      (..-1).overlap?(0..2).should == false
      (3..).overlap?(0..2).should == false
    end

    it "returns false when Ranges are not compatible" do
      (0..2).overlap?('a'..'d').should == false
    end

    it "return false when self is empty" do
      (2..0).overlap?(1..3).should == false
      (2...2).overlap?(1..3).should == false
      (1...1).overlap?(1...1).should == false
      (2..0).overlap?(2..0).should == false

      ('c'..'a').overlap?('b'..'d').should == false
      ('a'...'a').overlap?('b'..'d').should == false
      ('b'...'b').overlap?('b'...'b').should == false
      ('c'...'a').overlap?('c'...'a').should == false
    end

    it "return false when other Range is empty" do
      (1..3).overlap?(2..0).should == false
      (1..3).overlap?(2...2).should == false

      ('b'..'d').overlap?('c'..'a').should == false
      ('b'..'d').overlap?('c'...'c').should == false
    end

    it "takes into account exclusive end" do
      (0...2).overlap?(2..4).should == false
      (2..4).overlap?(0...2).should == false

      ('a'...'c').overlap?('c'..'e').should == false
      ('c'..'e').overlap?('a'...'c').should == false
    end
  end
end
