describe :hash_eql, shared: true do
  it "does not compare values when keys don't match" do
    value = mock('x')
    value.should_not_receive(:==)
    value.should_not_receive(:eql?)
    { 1 => value }.send(@method, { 2 => value }).should == false
  end

  it "returns false when the numbers of keys differ without comparing any elements" do
    obj = mock('x')
    h = { obj => obj }

    obj.should_not_receive(:==)
    obj.should_not_receive(:eql?)

    {}.send(@method, h).should == false
    h.send(@method, {}).should == false
  end

  it "first compares keys via hash" do
    x = mock('x')
    x.should_receive(:hash).any_number_of_times.and_return(0)
    y = mock('y')
    y.should_receive(:hash).any_number_of_times.and_return(0)

    { x => 1 }.send(@method, { y => 1 }).should == false
  end

  it "does not compare keys with different hash codes via eql?" do
    x = mock('x')
    y = mock('y')
    x.should_not_receive(:eql?)
    y.should_not_receive(:eql?)

    x.should_receive(:hash).any_number_of_times.and_return(0)
    y.should_receive(:hash).any_number_of_times.and_return(1)

    { x => 1 }.send(@method, { y => 1 }).should == false
  end

  it "computes equality for recursive hashes" do
    h = {}
    h[:a] = h
    h.send(@method, h[:a]).should == true
    (h == h[:a]).should == true
  end

  it "doesn't call to_hash on objects" do
    mock_hash = mock("fake hash")
    def mock_hash.to_hash() {} end
    {}.send(@method, mock_hash).should == false
  end

  it "computes equality for complex recursive hashes" do
    a, b = {}, {}
    a.merge! self: a, other: b
    b.merge! self: b, other: a
    a.send(@method, b).should == true # they both have the same structure!

    c = {}
    c.merge! other: c, self: c
    c.send(@method, a).should == true # subtle, but they both have the same structure!
    a[:delta] = c[:delta] = a
    c.send(@method, a).should == false # not quite the same structure, as a[:other][:delta] = nil
    c[:delta] = 42
    c.send(@method, a).should == false
    a[:delta] = 42
    c.send(@method, a).should == false
    b[:delta] = 42
    c.send(@method, a).should == true
  end

  it "computes equality for recursive hashes & arrays" do
    x, y, z = [], [], []
    a, b, c = {foo: x, bar: 42}, {foo: y, bar: 42}, {foo: z, bar: 42}
    x << a
    y << c
    z << b
    b.send(@method, c).should == true # they clearly have the same structure!
    y.send(@method, z).should == true
    a.send(@method, b).should == true # subtle, but they both have the same structure!
    x.send(@method, y).should == true
    y << x
    y.send(@method, z).should == false
    z << x
    y.send(@method, z).should == true

    a[:foo], a[:bar] = a[:bar], a[:foo]
    a.send(@method, b).should == false
    b[:bar] = b[:foo]
    b.send(@method, c).should == false
  end
end

describe :hash_eql_additional, shared: true do
  it "compares values when keys match" do
    x = mock('x')
    y = mock('y')
    def x.==(o) false end
    def y.==(o) false end
    def x.eql?(o) false end
    def y.eql?(o) false end
    { 1 => x }.send(@method, { 1 => y }).should == false

    x = mock('x')
    y = mock('y')
    def x.==(o) true end
    def y.==(o) true end
    def x.eql?(o) true end
    def y.eql?(o) true end
    { 1 => x }.send(@method, { 1 => y }).should == true
  end

  it "compares keys with eql? semantics" do
    { 1.0 => "x" }.send(@method, { 1.0 => "x" }).should == true
    { 1.0 => "x" }.send(@method, { 1.0 => "x" }).should == true
    { 1 => "x" }.send(@method, { 1.0 => "x" }).should == false
    { 1.0 => "x" }.send(@method, { 1 => "x" }).should == false
  end

  it "returns true if and only if other Hash has the same number of keys and each key-value pair matches" do
    a = { a: 5 }
    b = {}
    a.send(@method, b).should == false

    b[:a] = 5
    a.send(@method, b).should == true

    not_supported_on :opal do
      c = { "a" => 5 }
      a.send(@method, c).should == false
    end

    c = { "A" => 5 }
    a.send(@method, c).should == false

    c = { a: 6 }
    a.send(@method, c).should == false
  end

  it "does not call to_hash on hash subclasses" do
    { 5 => 6 }.send(@method, HashSpecs::ToHashHash[5 => 6]).should == true
  end

  it "ignores hash class differences" do
    h = { 1 => 2, 3 => 4 }
    HashSpecs::MyHash[h].send(@method, h).should == true
    HashSpecs::MyHash[h].send(@method, HashSpecs::MyHash[h]).should == true
    h.send(@method, HashSpecs::MyHash[h]).should == true
  end

  # Why isn't this true of eql? too ?
  it "compares keys with matching hash codes via eql?" do
    a = Array.new(2) do
      obj = mock('0')
      obj.should_receive(:hash).at_least(1).and_return(0)

      def obj.eql?(o)
        return true if self.equal?(o)
        false
      end

      obj
    end

    { a[0] => 1 }.send(@method, { a[1] => 1 }).should == false

    a = Array.new(2) do
      obj = mock('0')
      obj.should_receive(:hash).at_least(1).and_return(0)

      def obj.eql?(o)
        true
      end

      obj
    end

    { a[0] => 1 }.send(@method, { a[1] => 1 }).should == true
  end

  it "compares the values in self to values in other hash" do
    l_val = mock("left")
    r_val = mock("right")

    l_val.should_receive(:eql?).with(r_val).and_return(true)

    { 1 => l_val }.eql?({ 1 => r_val }).should == true
  end
end

describe :hash_eql_additional_more, shared: true do
  it "returns true if other Hash has the same number of keys and each key-value pair matches, even though the default-value are not same" do
    Hash.new(5).send(@method, Hash.new(1)).should == true
    Hash.new {|h, k| 1}.send(@method, Hash.new {}).should == true
    Hash.new {|h, k| 1}.send(@method, Hash.new(2)).should == true

    d = Hash.new {|h, k| 1}
    e = Hash.new {}
    d[1] = 2
    e[1] = 2
    d.send(@method, e).should == true
  end
end
