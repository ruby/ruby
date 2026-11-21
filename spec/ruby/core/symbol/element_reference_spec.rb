require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Symbol#[]" do
  describe "with an Integer index" do
    it "returns the character code of the element at the index" do
      :symbol[1].should == ?y
    end

    it "returns nil if the index starts from the end and is greater than the length" do
      :symbol[-10].should == nil
    end

    it "returns nil if the index is greater than the length" do
      :symbol[42].should == nil
    end
  end

  describe "with an Integer index and length" do
    describe "and a positive index and length" do
      it "returns a slice" do
        :symbol[1, 3].should == "ymb"
      end

      it "returns a blank slice if the length is 0" do
        :symbol[0, 0].should == ""
        :symbol[1, 0].should == ""
      end

      it "returns a slice of all remaining characters if the given length is greater than the actual length" do
        :symbol[1, 100].should == "ymbol"
      end

      it "returns nil if the index is greater than the length" do
        :symbol[10, 1].should == nil
      end
    end

    describe "and a positive index and negative length" do
      it "returns nil" do
        :symbol[0, -1].should == nil
        :symbol[1, -1].should == nil
      end
    end

    describe "and a negative index and positive length" do
      it "returns a slice starting from the end upto the length" do
        :symbol[-3, 2].should == "bo"
      end

      it "returns a blank slice if the length is 0" do
        :symbol[-1, 0].should == ""
      end

      it "returns a slice of all remaining characters if the given length is larger than the actual length" do
        :symbol[-4, 100].should == "mbol"
      end

      it "returns nil if the index is past the start" do
        :symbol[-10, 1].should == nil
      end
    end

    describe "and a negative index and negative length" do
      it "returns nil" do
        :symbol[-1, -1].should == nil
      end
    end

    describe "and a Float length" do
      it "converts the length to an Integer" do
        :symbol[2, 2.5].should == "mb"
      end
    end

    describe "and a nil length" do
      it "raises a TypeError" do
        -> { :symbol[1, nil] }.should.raise(TypeError)
      end
    end

    describe "and a length that cannot be converted into an Integer" do
      it "raises a TypeError when given an Array" do
        -> { :symbol[1, Array.new] }.should.raise(TypeError)
      end

      it "raises a TypeError when given an Hash" do
        -> { :symbol[1, Hash.new] }.should.raise(TypeError)
      end

      it "raises a TypeError when given an Object" do
        -> { :symbol[1, Object.new] }.should.raise(TypeError)
      end
    end
  end

  describe "with a Float index" do
    it "converts the index to an Integer" do
      :symbol[1.5].should == ?y
    end
  end

  describe "with a nil index" do
    it "raises a TypeError" do
      -> { :symbol[nil] }.should.raise(TypeError)
    end
  end

  describe "with an index that cannot be converted into an Integer" do
    it "raises a TypeError when given an Array" do
      -> { :symbol[Array.new] }.should.raise(TypeError)
    end

    it "raises a TypeError when given an Hash" do
      -> { :symbol[Hash.new] }.should.raise(TypeError)
    end

    it "raises a TypeError when given an Object" do
      -> { :symbol[Object.new] }.should.raise(TypeError)
    end
  end

  describe "with a Range slice" do
    describe "that is within bounds" do
      it "returns a slice if both range values begin at the start and are within bounds" do
        :symbol[1..4].should == "ymbo"
      end

      it "returns a slice if the first range value begins at the start and the last begins at the end" do
        :symbol[1..-1].should == "ymbol"
      end

      it "returns a slice if the first range value begins at the end and the last begins at the end" do
        :symbol[-4..-1].should == "mbol"
      end
    end

    describe "that is out of bounds" do
      it "returns nil if the first range value begins past the end" do
        :symbol[10..12].should == nil
      end

      it "returns a blank string if the first range value is within bounds and the last range value is not" do
        :symbol[-2..-10].should == ""
        :symbol[2..-10].should == ""
      end

      it "returns nil if the first range value starts from the end and is within bounds and the last value starts from the end and is greater than the length" do
        :symbol[-10..-12].should == nil
      end

      it "returns nil if the first range value starts from the end and is out of bounds and the last value starts from the end and is less than the length" do
        :symbol[-10..-2].should == nil
      end
    end

    describe "with Float values" do
      it "converts the first value to an Integer" do
        :symbol[0.5..2].should == "sym"
      end

      it "converts the last value to an Integer" do
        :symbol[0..2.5].should == "sym"
      end
    end
  end

  describe "with a Range subclass slice" do
    it "returns a slice" do
      range = SymbolSpecs::MyRange.new(1, 4)
      :symbol[range].should == "ymbo"
    end
  end

  describe "with a Regex slice" do
    describe "without a capture index" do
      it "returns a string of the match" do
        :symbol[/[^bol]+/].should == "sym"
      end

      it "returns nil if the expression does not match" do
        :symbol[/0-9/].should == nil
      end

      it "sets $~ to the MatchData if there is a match" do
        :symbol[/[^bol]+/]
        $~[0].should == "sym"
      end

      it "does not set $~ if there if there is not a match" do
        :symbol[/[0-9]+/]
        $~.should == nil
      end
    end

    describe "with a capture index" do
      it "returns a string of the complete match if the capture index is 0" do
        :symbol[/(sy)(mb)(ol)/, 0].should == "symbol"
      end

      it "returns a string for the matched capture at the given index" do
        :symbol[/(sy)(mb)(ol)/, 1].should == "sy"
        :symbol[/(sy)(mb)(ol)/, -1].should == "ol"
      end

      it "returns nil if there is no capture for the index" do
        :symbol[/(sy)(mb)(ol)/, 4].should == nil
        :symbol[/(sy)(mb)(ol)/, -4].should == nil
      end

      it "converts the index to an Integer" do
        :symbol[/(sy)(mb)(ol)/, 1.5].should == "sy"
      end

      describe "and an index that cannot be converted to an Integer" do
        it "raises a TypeError when given an Hash" do
          -> { :symbol[/(sy)(mb)(ol)/, Hash.new] }.should.raise(TypeError)
        end

        it "raises a TypeError when given an Array" do
          -> { :symbol[/(sy)(mb)(ol)/, Array.new] }.should.raise(TypeError)
        end

        it "raises a TypeError when given an Object" do
          -> { :symbol[/(sy)(mb)(ol)/, Object.new] }.should.raise(TypeError)
        end
      end

      it "raises a TypeError if the index is nil" do
        -> { :symbol[/(sy)(mb)(ol)/, nil] }.should.raise(TypeError)
      end

      it "sets $~ to the MatchData if there is a match" do
        :symbol[/(sy)(mb)(ol)/, 0]
        $~[0].should == "symbol"
        $~[1].should == "sy"
        $~[2].should == "mb"
        $~[3].should == "ol"
      end

      it "does not set $~ to the MatchData if there is not a match" do
        :symbol[/0-9/, 0]
        $~.should == nil
      end
    end
  end

  describe "with a String slice" do
    it "does not set $~" do
      $~ = nil
      :symbol["sym"]
      $~.should == nil
    end

    it "returns a string if there is match" do
      :symbol["ymb"].should == "ymb"
    end

    it "returns nil if there is not a match" do
      :symbol["foo"].should == nil
    end
  end
end
