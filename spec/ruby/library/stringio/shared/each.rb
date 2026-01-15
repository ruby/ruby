describe :stringio_each_separator, shared: true do
  before :each do
    @io = StringIO.new("a b c d e\n1 2 3 4 5")
  end

  it "uses the passed argument as the line separator" do
    seen = []
    @io.send(@method, " ") {|s| seen << s}
    seen.should == ["a ", "b ", "c ", "d ", "e\n1 ", "2 ", "3 ", "4 ", "5"]
  end

  it "does not change $_" do
    $_ = "test"
    @io.send(@method, " ") { |s| s}
    $_.should == "test"
  end

  it "returns self" do
    @io.send(@method) {|l| l }.should equal(@io)
  end

  it "tries to convert the passed separator to a String using #to_str" do
    obj = mock("to_str")
    obj.stub!(:to_str).and_return(" ")

    seen = []
    @io.send(@method, obj) { |l| seen << l }
    seen.should == ["a ", "b ", "c ", "d ", "e\n1 ", "2 ", "3 ", "4 ", "5"]
  end

  it "yields self's content starting from the current position when the passed separator is nil" do
    seen = []
    io = StringIO.new("1 2 1 2 1 2")
    io.pos = 2
    io.send(@method, nil) {|s| seen << s}
    seen.should == ["2 1 2 1 2"]
  end

  it "yields each paragraph with all separation characters when passed an empty String as separator" do
    seen = []
    io = StringIO.new("para1\n\npara2\n\n\npara3")
    io.send(@method, "") {|s| seen << s}
    seen.should == ["para1\n\n", "para2\n\n\n", "para3"]
  end
end

describe :stringio_each_no_arguments, shared: true do
  before :each do
    @io = StringIO.new("a b c d e\n1 2 3 4 5")
  end

  it "yields each line to the passed block" do
    seen = []
    @io.send(@method) {|s| seen << s }
    seen.should == ["a b c d e\n", "1 2 3 4 5"]
  end

  it "yields each line starting from the current position" do
    seen = []
    @io.pos = 4
    @io.send(@method) {|s| seen << s }
    seen.should == ["c d e\n", "1 2 3 4 5"]
  end

  it "does not change $_" do
    $_ = "test"
    @io.send(@method) { |s| s}
    $_.should == "test"
  end

  it "uses $/ as the default line separator" do
    seen = []
    begin
      old_rs = $/
      suppress_warning {$/ = " "}
      @io.send(@method) {|s| seen << s }
      seen.should eql(["a ", "b ", "c ", "d ", "e\n1 ", "2 ", "3 ", "4 ", "5"])
    ensure
      suppress_warning {$/ = old_rs}
    end
  end

  it "returns self" do
    @io.send(@method) {|l| l }.should equal(@io)
  end

  it "returns an Enumerator when passed no block" do
    enum = @io.send(@method)
    enum.instance_of?(Enumerator).should be_true

    seen = []
    enum.each { |b| seen << b }
    seen.should == ["a b c d e\n", "1 2 3 4 5"]
  end
end

describe :stringio_each_not_readable, shared: true do
  it "raises an IOError" do
    io = StringIO.new(+"a b c d e", "w")
    -> { io.send(@method) { |b| b } }.should raise_error(IOError)

    io = StringIO.new("a b c d e")
    io.close_read
    -> { io.send(@method) { |b| b } }.should raise_error(IOError)
  end
end

describe :stringio_each_chomp, shared: true do
  it "yields each line with removed newline characters to the passed block" do
    seen = []
    io = StringIO.new("a b \rc d e\n1 2 3 4 5\r\nthe end")
    io.send(@method, chomp: true) {|s| seen << s }
    seen.should == ["a b \rc d e", "1 2 3 4 5", "the end"]
  end

  it "returns each line with removed newline characters when called without block" do
    seen = []
    io = StringIO.new("a b \rc d e\n1 2 3 4 5\r\nthe end")
    enum = io.send(@method, chomp: true)
    enum.each {|s| seen << s }
    seen.should == ["a b \rc d e", "1 2 3 4 5", "the end"]
  end
end

describe :stringio_each_separator_and_chomp, shared: true do
  it "yields each line with removed separator to the passed block" do
    seen = []
    io = StringIO.new("a b \nc d e|1 2 3 4 5\n|the end")
    io.send(@method, "|", chomp: true) {|s| seen << s }
    seen.should == ["a b \nc d e", "1 2 3 4 5\n", "the end"]
  end

  it "returns each line with removed separator when called without block" do
    seen = []
    io = StringIO.new("a b \nc d e|1 2 3 4 5\n|the end")
    enum = io.send(@method, "|", chomp: true)
    enum.each {|s| seen << s }
    seen.should == ["a b \nc d e", "1 2 3 4 5\n", "the end"]
  end
end

describe :stringio_each_limit, shared: true do
  before :each do
    @io = StringIO.new("a b c d e\n1 2 3 4 5")
  end

  it "returns the data read until the limit is met" do
    seen = []
    @io.send(@method, 4) { |s| seen << s }
    seen.should == ["a b ", "c d ", "e\n", "1 2 ", "3 4 ", "5"]
  end
end

describe :stringio_each_separator_and_limit, shared: true do
  before :each do
    @io = StringIO.new("this>is>an>example")
  end

  it "returns the data read until the limit is consumed or the separator is met" do
    @io.send(@method, '>', 8) { |s| break s }.should == "this>"
    @io.send(@method, '>', 2) { |s| break s }.should == "is"
    @io.send(@method, '>', 10) { |s| break s }.should == ">"
    @io.send(@method, '>', 6) { |s| break s }.should == "an>"
    @io.send(@method, '>', 5) { |s| break s }.should == "examp"
  end

  it "truncates the multi-character separator at the end to meet the limit" do
    @io.send(@method, "is>an", 7) { |s| break s }.should == "this>is"
  end

  it "does not change $_" do
    $_ = "test"
    @io.send(@method, '>', 8) { |s| s }
    $_.should == "test"
  end

  it "updates self's lineno by one" do
    @io.send(@method, '>', 3) { |s| break s }
    @io.lineno.should eql(1)

    @io.send(@method, '>', 3) { |s| break s }
    @io.lineno.should eql(2)

    @io.send(@method, '>', 3) { |s| break s }
    @io.lineno.should eql(3)
  end

  it "tries to convert the passed separator to a String using #to_str" do # TODO
    obj = mock('to_str')
    obj.should_receive(:to_str).and_return('>')

    seen = []
    @io.send(@method, obj, 5) { |s| seen << s }
    seen.should == ["this>", "is>", "an>", "examp", "le"]
  end

  it "does not raise TypeError if passed separator is nil" do
    @io.send(@method, nil, 5) { |s| break s }.should == "this>"
  end

  it "tries to convert the passed limit to an Integer using #to_int" do # TODO
    obj = mock('to_int')
    obj.should_receive(:to_int).and_return(5)

    seen = []
    @io.send(@method, '>', obj) { |s| seen << s }
    seen.should == ["this>", "is>", "an>", "examp", "le"]
  end
end
