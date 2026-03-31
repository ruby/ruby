describe :stringio_gets_separator, shared: true do
  describe "when passed [separator]" do
    before :each do
      @io = StringIO.new("this>is>an>example")
    end

    it "returns the data read till the next occurrence of the passed separator" do
      @io.send(@method, ">").should == "this>"
      @io.send(@method, ">").should == "is>"
      @io.send(@method, ">").should == "an>"
      @io.send(@method, ">").should == "example"
    end

    it "sets $_ to the read content" do
      @io.send(@method, ">")
      $_.should == "this>"
      @io.send(@method, ">")
      $_.should == "is>"
      @io.send(@method, ">")
      $_.should == "an>"
      @io.send(@method, ">")
      $_.should == "example"
    end

    it "accepts string as separator" do
      @io.send(@method, "is>")
      $_.should == "this>"
      @io.send(@method, "an>")
      $_.should == "is>an>"
      @io.send(@method, "example")
      $_.should == "example"
    end

    it "updates self's lineno by one" do
      @io.send(@method, ">")
      @io.lineno.should eql(1)

      @io.send(@method, ">")
      @io.lineno.should eql(2)

      @io.send(@method, ">")
      @io.lineno.should eql(3)
    end

    it "returns the next paragraph when the passed separator is an empty String" do
      io = StringIO.new("this is\n\nan example")
      io.send(@method, "").should == "this is\n\n"
      io.send(@method, "").should == "an example"
    end

    it "returns the remaining content starting at the current position when passed nil" do
      io = StringIO.new("this is\n\nan example")
      io.pos = 5
      io.send(@method, nil).should == "is\n\nan example"
    end

    it "tries to convert the passed separator to a String using #to_str" do
      obj = mock('to_str')
      obj.should_receive(:to_str).and_return(">")
      @io.send(@method, obj).should == "this>"
    end
  end
end

describe :stringio_gets_limit, shared: true do
  describe "when passed [limit]" do
    before :each do
      @io = StringIO.new("this>is>an>example")
    end

    it "returns the data read until the limit is met" do
      @io.send(@method, 4).should == "this"
      @io.send(@method, 3).should == ">is"
      @io.send(@method, 5).should == ">an>e"
      @io.send(@method, 6).should == "xample"
    end

    it "sets $_ to the read content" do
      @io.send(@method, 4)
      $_.should == "this"
      @io.send(@method, 3)
      $_.should == ">is"
      @io.send(@method, 5)
      $_.should == ">an>e"
      @io.send(@method, 6)
      $_.should == "xample"
    end

    it "updates self's lineno by one" do
      @io.send(@method, 3)
      @io.lineno.should eql(1)

      @io.send(@method, 3)
      @io.lineno.should eql(2)

      @io.send(@method, 3)
      @io.lineno.should eql(3)
    end

    it "tries to convert the passed limit to an Integer using #to_int" do
      obj = mock('to_int')
      obj.should_receive(:to_int).and_return(4)
      @io.send(@method, obj).should == "this"
    end

    it "returns a blank string when passed a limit of 0" do
      @io.send(@method, 0).should == ""
    end

    it "ignores it when passed a negative limit" do
      @io.send(@method, -4).should == "this>is>an>example"
    end
  end
end

describe :stringio_gets_separator_and_limit, shared: true do
  describe "when passed [separator] and [limit]" do
    before :each do
      @io = StringIO.new("this>is>an>example")
    end

    it "returns the data read until the limit is consumed or the separator is met" do
      @io.send(@method, '>', 8).should == "this>"
      @io.send(@method, '>', 2).should == "is"
      @io.send(@method, '>', 10).should == ">"
      @io.send(@method, '>', 6).should == "an>"
      @io.send(@method, '>', 5).should == "examp"
    end

    it "truncates the multi-character separator at the end to meet the limit" do
      @io.send(@method, "is>an", 7).should == "this>is"
    end

    it "sets $_ to the read content" do
      @io.send(@method, '>', 8)
      $_.should == "this>"
      @io.send(@method, '>', 2)
      $_.should == "is"
      @io.send(@method, '>', 10)
      $_.should == ">"
      @io.send(@method, '>', 6)
      $_.should == "an>"
      @io.send(@method, '>', 5)
      $_.should == "examp"
    end

    it "updates self's lineno by one" do
      @io.send(@method, '>', 3)
      @io.lineno.should eql(1)

      @io.send(@method, '>', 3)
      @io.lineno.should eql(2)

      @io.send(@method, '>', 3)
      @io.lineno.should eql(3)
    end

    it "tries to convert the passed separator to a String using #to_str" do
      obj = mock('to_str')
      obj.should_receive(:to_str).and_return('>')
      @io.send(@method, obj, 5).should == "this>"
    end

    it "does not raise TypeError if passed separator is nil" do
      @io.send(@method, nil, 5).should == "this>"
    end

    it "tries to convert the passed limit to an Integer using #to_int" do
      obj = mock('to_int')
      obj.should_receive(:to_int).and_return(5)
      @io.send(@method, '>', obj).should == "this>"
    end
  end
end

describe :stringio_gets_no_argument, shared: true do
  describe "when passed no argument" do
    before :each do
      @io = StringIO.new("this is\nan example\nfor StringIO#gets")
    end

    it "returns the data read till the next occurrence of $/ or till eof" do
      @io.send(@method).should == "this is\n"

      begin
        old_sep = $/
        suppress_warning {$/ = " "}
        @io.send(@method).should == "an "
        @io.send(@method).should == "example\nfor "
        @io.send(@method).should == "StringIO#gets"
      ensure
        suppress_warning {$/ = old_sep}
      end
    end

    it "sets $_ to the read content" do
      @io.send(@method)
      $_.should == "this is\n"
      @io.send(@method)
      $_.should == "an example\n"
      @io.send(@method)
      $_.should == "for StringIO#gets"
    end

    it "updates self's position" do
      @io.send(@method)
      @io.pos.should eql(8)

      @io.send(@method)
      @io.pos.should eql(19)

      @io.send(@method)
      @io.pos.should eql(36)
    end

    it "updates self's lineno" do
      @io.send(@method)
      @io.lineno.should eql(1)

      @io.send(@method)
      @io.lineno.should eql(2)

      @io.send(@method)
      @io.lineno.should eql(3)
    end
  end
end

describe :stringio_gets_chomp, shared: true do
  describe "when passed [chomp]" do
    it "returns the data read without a trailing newline character" do
      io = StringIO.new("this>is>an>example\n")
      io.send(@method, chomp: true).should == "this>is>an>example"
    end
  end
end

describe :stringio_gets_write_only, shared: true do
  describe "when in write-only mode" do
    it "raises an IOError" do
      io = StringIO.new(+"xyz", "w")
      -> { io.send(@method) }.should raise_error(IOError)

      io = StringIO.new("xyz")
      io.close_read
      -> { io.send(@method) }.should raise_error(IOError)
    end
  end
end
