describe :string_dedup, shared: true do
  it 'returns self if the String is frozen' do
    input  = 'foo'.freeze
    output = input.send(@method)

    output.should equal(input)
    output.should.frozen?
  end

  it 'returns a frozen copy if the String is not frozen' do
    input  = 'foo'
    output = input.send(@method)

    output.should.frozen?
    output.should_not equal(input)
    output.should == 'foo'
  end

  it "returns the same object for equal unfrozen strings" do
    origin = "this is a string"
    dynamic = %w(this is a string).join(' ')

    origin.should_not equal(dynamic)
    origin.send(@method).should equal(dynamic.send(@method))
  end

  it "returns the same object when it's called on the same String literal" do
    "unfrozen string".send(@method).should equal("unfrozen string".send(@method))
    "unfrozen string".send(@method).should_not equal("another unfrozen string".send(@method))
  end

  it "deduplicates frozen strings" do
    dynamic = %w(this string is frozen).join(' ').freeze

    dynamic.should_not equal("this string is frozen".freeze)

    dynamic.send(@method).should equal("this string is frozen".freeze)
    dynamic.send(@method).should equal("this string is frozen".send(@method).freeze)
  end

  it "does not deduplicate a frozen string when it has instance variables" do
    dynamic = %w(this string is frozen).join(' ')
    dynamic.instance_variable_set(:@a, 1)
    dynamic.freeze

    dynamic.send(@method).should_not equal("this string is frozen".freeze)
    dynamic.send(@method).should_not equal("this string is frozen".send(@method).freeze)
    dynamic.send(@method).should equal(dynamic)
  end

  it "interns the provided string if it is frozen" do
    dynamic = "this string is unique and frozen #{rand}".freeze
    dynamic.send(@method).should equal(dynamic)
  end
end
