require_relative '../fixtures/classes'

describe :data_inspect, shared: true do
  it "returns a string representation showing members and values" do
    a = DataSpecs::Measure.new(42, "km")
    a.send(@method).should == '#<data DataSpecs::Measure amount=42, unit="km">'
  end

  it "returns a string representation without the class name for anonymous structs" do
    Data.define(:a).new("").send(@method).should == '#<data a="">'
  end

  it "returns a string representation without the class name for structs nested in anonymous classes" do
    c = Class.new
    c.class_eval <<~DOC
        Foo = Data.define(:a)
      DOC

    c::Foo.new("").send(@method).should == '#<data a="">'
  end

  it "returns a string representation without the class name for structs nested in anonymous modules" do
    m = Module.new
    m.class_eval <<~DOC
        Foo = Data.define(:a)
      DOC

    m::Foo.new("").send(@method).should == '#<data a="">'
  end

  it "does not call #name method" do
    struct = DataSpecs::MeasureWithOverriddenName.new(42, "km")
    struct.send(@method).should == '#<data DataSpecs::MeasureWithOverriddenName amount=42, unit="km">'
  end

  it "does not call #name method when struct is anonymous" do
    klass = Class.new(DataSpecs::Measure) do
      def self.name
        "A"
      end
    end
    struct = klass.new(42, "km")
    struct.send(@method).should == '#<data amount=42, unit="km">'
  end

  context "recursive structure" do
    it "returns string representation with recursive attribute replaced with ..." do
      a = DataSpecs::Measure.allocate
      a.send(:initialize, amount: 42, unit: a)

      a.send(@method).should == "#<data DataSpecs::Measure amount=42, unit=#<data DataSpecs::Measure:...>>"
    end

    it "returns string representation with recursive attribute replaced with ... when an anonymous class" do
      klass = Class.new(DataSpecs::Measure)
      a = klass.allocate
      a.send(:initialize, amount: 42, unit: a)

      a.send(@method).should =~ /#<data amount=42, unit=#<data #<Class:0x.+?>:\.\.\.>>/
    end
  end
end
