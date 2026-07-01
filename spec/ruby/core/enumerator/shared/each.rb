# #each passes source-yielded values to the block by ordinary block arity
# (rb_yield_values2 semantics in CRuby), unlike the Enumerable collection methods
# which pack them via rb_enum_values_pack() (see enumerable/shared/value_packing.rb).
describe :enum_each, shared: true do
  # @object must be set to a Proc that wraps an Enumerator into the receiver
  # under test (e.g. -> e { e } for Enumerator#each, -> e { e.lazy } for Lazy#each).
  describe "with a source that yields multiple values" do
    before :each do
      @enum = @object.call(Enumerator.new { |y| y.yield 1, 2; y.yield 3, 4 })
    end

    it "yields the first value to a single-argument block" do
      collected = []
      @enum.each { |x| collected << x }
      collected.should == [1, 3]
    end

    it "yields each value to a multi-argument block" do
      collected = []
      @enum.each { |x, y| collected << [x, y] }
      collected.should == [[1, 2], [3, 4]]
    end

    it "gathers the values for a splat block" do
      collected = []
      @enum.each { |*args| collected << args }
      collected.should == [[1, 2], [3, 4]]
    end
  end

  describe "with a source that yields a single value" do
    it "yields the value to a single-argument block" do
      collected = []
      @object.call(Enumerator.new { |y| y.yield 7; y.yield 8 }).each { |x| collected << x }
      collected.should == [7, 8]
    end
  end

  describe "with a source that yields no value" do
    it "yields nil to a single-argument block" do
      collected = []
      @object.call(Enumerator.new { |y| y.yield; y.yield }).each { |x| collected << x }
      collected.should == [nil, nil]
    end
  end
end
