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
    obj.frozen?.should == true
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
      obj.tainted?.should == true
      @specs.set_flags(obj, initial).should == initial
      obj.tainted?.should == false
      @specs.set_flags(obj, @freeze | initial).should == @freeze | initial
      obj.frozen?.should == true

      obj, _ = @data.call
      @specs.set_flags(obj, @freeze | @taint | initial).should == @freeze | @taint | initial
      obj.tainted?.should == true
      obj.frozen?.should == true
    end
  end

  it "supports user flags" do
    obj, _ = @data.call
    @specs.get_flags(obj) == 0
    @specs.set_flags(obj, 1 << 14 | 1 << 16).should == 1 << 14 | 1 << 16
    @specs.get_flags(obj).should == 1 << 14 | 1 << 16
    @specs.set_flags(obj, 0).should == 0
  end

  it "supports copying the flags from one object over to the other" do
    obj1, obj2 = @data.call
    @specs.set_flags(obj1, @taint | 1 << 14 | 1 << 16)
    @specs.copy_flags(obj2, obj1)
    @specs.get_flags(obj2).should == @taint | 1 << 14 | 1 << 16
    @specs.set_flags(obj1, 0)
    @specs.copy_flags(obj2, obj1)
    @specs.get_flags(obj2).should == 0
  end

  it "supports retrieving the (meta)class" do
    obj, _ = @data.call
    @specs.get_klass(obj).should == obj.class
    obj.singleton_class # ensure the singleton class exists
    @specs.get_klass(obj).should == obj.singleton_class
  end
end
