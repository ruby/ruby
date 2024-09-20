describe :module_attr_added, shared: true do
  it "calls method_added for normal classes" do
    ScratchPad.record []

    cls = Class.new do
      class << self
        def method_added(name)
          ScratchPad.recorded << name
        end
      end
    end

    cls.send(@method, :foo)

    ScratchPad.recorded.each {|name| name.to_s.should =~ /foo[=]?/}
  end

  it "calls singleton_method_added for singleton classes" do
    ScratchPad.record []
    cls = Class.new do
      class << self
        def singleton_method_added(name)
          # called for this def so ignore it
          return if name == :singleton_method_added
          ScratchPad.recorded << name
        end
      end
    end

    cls.singleton_class.send(@method, :foo)

    ScratchPad.recorded.each {|name| name.to_s.should =~ /foo[=]?/}
  end
end
