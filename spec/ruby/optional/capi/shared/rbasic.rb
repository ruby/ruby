describe :rbasic, shared: true do

  before :all do
    specs = CApiRBasicSpecs.new
    @taint = specs.taint_flag
    @freeze = specs.freeze_flag
  end

  it "reports the appropriate FREEZE flag for the object when reading" do
    obj, _ = @data.call
    initial = @specs.get_flags(obj)
    obj.freeze
    @specs.get_flags(obj).should == @freeze | initial
  end

  it "supports setting the FREEZE flag" do
    obj, _ = @data.call
    initial = @specs.get_flags(obj)
    @specs.set_flags(obj, @freeze | initial).should == @freeze | initial
    obj.should.frozen?
  end

  ruby_version_is ""..."2.7" do
    it "reports the appropriate FREEZE and TAINT flags for the object when reading" do
      obj, _ = @data.call
      initial = @specs.get_flags(obj)
      obj.taint
      @specs.get_flags(obj).should == @taint | initial
      obj.untaint
      @specs.get_flags(obj).should == initial
      obj.freeze
      @specs.get_flags(obj).should == @freeze | initial

      obj, _ = @data.call
      obj.taint
      obj.freeze
      @specs.get_flags(obj).should == @freeze | @taint | initial
    end

    it "supports setting the FREEZE and TAINT flags" do
      obj, _ = @data.call
      initial = @specs.get_flags(obj)
      @specs.set_flags(obj, @taint | initial).should == @taint | initial
      obj.should.tainted?
      @specs.set_flags(obj, initial).should == initial
      obj.should_not.tainted?
      @specs.set_flags(obj, @freeze | initial).should == @freeze | initial
      obj.should.frozen?

      obj, _ = @data.call
      @specs.set_flags(obj, @freeze | @taint | initial).should == @freeze | @taint | initial
      obj.should.tainted?
      obj.should.frozen?
    end
  end

  it "supports user flags" do
    obj, _ = @data.call
    initial = @specs.get_flags(obj)
    @specs.set_flags(obj, 1 << 14 | 1 << 16 | initial).should == 1 << 14 | 1 << 16 | initial
    @specs.get_flags(obj).should == 1 << 14 | 1 << 16 | initial
    @specs.set_flags(obj, initial).should == initial
  end

  it "supports copying the flags from one object over to the other" do
    obj1, obj2 = @data.call
    initial = @specs.get_flags(obj1)
    @specs.get_flags(obj2).should == initial
    @specs.set_flags(obj1, 1 << 14 | 1 << 16 | initial)
    @specs.copy_flags(obj2, obj1)
    @specs.get_flags(obj2).should == 1 << 14 | 1 << 16 | initial
    @specs.set_flags(obj1, initial)
    @specs.copy_flags(obj2, obj1)
    @specs.get_flags(obj2).should == initial
  end

  it "supports retrieving the (meta)class" do
    obj, _ = @data.call
    @specs.get_klass(obj).should == obj.class
    obj.singleton_class # ensure the singleton class exists
    @specs.get_klass(obj).should == obj.singleton_class
  end
end
