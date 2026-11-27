# This is the behavior of rb_enum_values_pack() in CRuby
describe :enumerable_value_packing, shared: true do
  # @take must be set to a Proc that returns the take-result whose #each
  # yields packed values (e.g. -> e { e.take(1) } or -> e { e.lazy.take(1) }).

  it "yields a single nil for a zero-argument source yield" do
    e = Enumerator.new { |y| y.yield }
    args = nil
    @take.call(e).each { |*a| args = a }
    args.should == [nil]
  end

  it "yields the value for a single-argument source yield" do
    e = Enumerator.new { |y| y.yield :v }
    args = nil
    @take.call(e).each { |*a| args = a }
    args.should == [:v]
  end

  it "yields a packed Array for a multi-argument source yield" do
    e = Enumerator.new { |y| y.yield 1, 2 }
    args = nil
    @take.call(e).each { |*a| args = a }
    args.should == [[1, 2]]
  end
end
