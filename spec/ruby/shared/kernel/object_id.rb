# These examples hold for both BasicObject#__id__ and Kernel#object_id.
describe :object_id, shared: true do
  it "returns an integer" do
    o1 = @object.new
    o1.__send__(@method).should be_kind_of(Integer)
  end

  it "returns the same value on all calls to id for a given object" do
    o1 = @object.new
    o1.__send__(@method).should == o1.__send__(@method)
  end

  it "returns different values for different objects" do
    o1 = @object.new
    o2 = @object.new
    o1.__send__(@method).should_not == o2.__send__(@method)
  end

  it "returns the same value for two Fixnums with the same value" do
    o1 = 1
    o2 = 1
    o1.send(@method).should == o2.send(@method)
  end

  it "returns the same value for two Symbol literals" do
    o1 = :hello
    o2 = :hello
    o1.send(@method).should == o2.send(@method)
  end

  it "returns the same value for two true literals" do
    o1 = true
    o2 = true
    o1.send(@method).should == o2.send(@method)
  end

  it "returns the same value for two false literals" do
    o1 = false
    o2 = false
    o1.send(@method).should == o2.send(@method)
  end

  it "returns the same value for two nil literals" do
    o1 = nil
    o2 = nil
    o1.send(@method).should == o2.send(@method)
  end

  it "returns a different value for two Bignum literals" do
    o1 = 2e100.to_i
    o2 = 2e100.to_i
    o1.send(@method).should_not == o2.send(@method)
  end

  guard -> { "test".frozen? && "test".equal?("test") } do # --enable-frozen-string-literal in $RUBYOPT
    it "returns the same value for two identical String literals" do
      o1 = "hello"
      o2 = "hello"
      o1.send(@method).should == o2.send(@method)
    end
  end

  guard -> { "test".frozen? && !"test".equal?("test") } do # chilled string literals
    it "returns a different frozen value for two String literals" do
      o1 = "hello"
      o2 = "hello"
      o1.send(@method).should_not == o2.send(@method)
      o1.frozen?.should == true
      o2.frozen?.should == true
    end
  end

  guard -> { !"test".frozen? } do
    it "returns a different value for two String literals" do
      o1 = "hello"
      o2 = "hello"
      o1.send(@method).should_not == o2.send(@method)
    end
  end

  it "returns a different value for an object and its dup" do
    o1 = mock("object")
    o2 = o1.dup
    o1.send(@method).should_not == o2.send(@method)
  end

  it "returns a different value for two numbers near the 32 bit Fixnum limit" do
    o1 = -1
    o2 = 2 ** 30 - 1

    o1.send(@method).should_not == o2.send(@method)
  end

  it "returns a different value for two numbers near the 64 bit Fixnum limit" do
    o1 = -1
    o2 = 2 ** 62 - 1

    o1.send(@method).should_not == o2.send(@method)
  end
end
