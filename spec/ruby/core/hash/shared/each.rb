describe :hash_each, shared: true do

  # This is inconsistent with below, MRI checks the block arity in rb_hash_each_pair()
  it "yields a [[key, value]] Array for each pair to a block expecting |*args|" do
    all_args = []
    { 1 => 2, 3 => 4 }.send(@method) { |*args| all_args << args }
    all_args.sort.should == [[[1, 2]], [[3, 4]]]
  end

  it "yields the key and value of each pair to a block expecting |key, value|" do
    r = {}
    h = { a: 1, b: 2, c: 3, d: 5 }
    h.send(@method) { |k,v| r[k.to_s] = v.to_s }.should equal(h)
    r.should == { "a" => "1", "b" => "2", "c" => "3", "d" => "5" }
  end

  it "yields the key only to a block expecting |key,|" do
    ary = []
    h = { "a" => 1, "b" => 2, "c" => 3 }
    h.send(@method) { |k,| ary << k }
    ary.sort.should == ["a", "b", "c"]
  end

  ruby_version_is ""..."3.0" do
    it "yields 2 values and not an Array of 2 elements when given a callable of arity 2" do
      obj = Object.new
      def obj.foo(key, value)
        ScratchPad << key << value
      end

      ScratchPad.record([])
      { "a" => 1 }.send(@method, &obj.method(:foo))
      ScratchPad.recorded.should == ["a", 1]

      ScratchPad.record([])
      { "a" => 1 }.send(@method, &-> key, value { ScratchPad << key << value })
      ScratchPad.recorded.should == ["a", 1]
    end
  end

  ruby_version_is "3.0" do
    it "yields an Array of 2 elements when given a callable of arity 2" do
      obj = Object.new
      def obj.foo(key, value)
      end

      -> {
        { "a" => 1 }.send(@method, &obj.method(:foo))
      }.should raise_error(ArgumentError)

      -> {
        { "a" => 1 }.send(@method, &-> key, value { })
      }.should raise_error(ArgumentError)
    end
  end

  it "uses the same order as keys() and values()" do
    h = { a: 1, b: 2, c: 3, d: 5 }
    keys = []
    values = []

    h.send(@method) do |k, v|
      keys << k
      values << v
    end

    keys.should == h.keys
    values.should == h.values
  end

  # Confirming the argument-splatting works from child class for both k, v and [k, v]
  it "properly expands (or not) child class's 'each'-yielded args" do
    cls1 = Class.new(Hash) do
      attr_accessor :k_v
      def each
        super do |k, v|
          @k_v = [k, v]
          yield k, v
        end
      end
    end

    cls2 = Class.new(Hash) do
      attr_accessor :k_v
      def each
        super do |k, v|
          @k_v = [k, v]
          yield([k, v])
        end
      end
    end

    obj1 = cls1.new
    obj1['a'] = 'b'
    obj1.map {|k, v| [k, v]}.should == [['a', 'b']]
    obj1.k_v.should == ['a', 'b']

    obj2 = cls2.new
    obj2['a'] = 'b'
    obj2.map {|k, v| [k, v]}.should == [['a', 'b']]
    obj2.k_v.should == ['a', 'b']
  end
end
