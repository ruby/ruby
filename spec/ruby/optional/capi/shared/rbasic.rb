describe :rbasic, shared: true do

  before :all do
    specs = CApiRBasicSpecs.new
    @taint = ruby_version_is(''...'3.1') ? specs.taint_flag : 0
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

  it "supports retrieving the (meta)class" do
    obj, _ = @data.call
    @specs.get_klass(obj).should == obj.class
    obj.singleton_class # ensure the singleton class exists
    @specs.get_klass(obj).should == obj.singleton_class
  end
end
