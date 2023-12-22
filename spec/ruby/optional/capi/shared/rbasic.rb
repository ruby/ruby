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
    (@specs.get_flags(obj) & 0xFFFF).should == (@freeze | initial) & 0xFFFF
  end

  it "supports setting the FREEZE flag" do
    obj, _ = @data.call
    initial = @specs.get_flags(obj)
    @specs.set_flags(obj, @freeze | initial).should == @freeze | initial
    obj.should.frozen?
  end

  it "supports retrieving the (meta)class" do
    obj, _ = @data.call
    @specs.get_klass(obj).should == obj.class
    obj.singleton_class # ensure the singleton class exists
    @specs.get_klass(obj).should == obj.singleton_class
  end
end
