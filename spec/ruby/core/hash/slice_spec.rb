require_relative '../../spec_helper'

ruby_version_is "2.5" do
  describe "Hash#slice" do
    before :each do
      @hash = { a: 1, b: 2, c: 3 }
    end

    it "returns a new empty hash without arguments" do
      ret = @hash.slice
      ret.should_not equal(@hash)
      ret.should be_an_instance_of(Hash)
      ret.should == {}
    end

    it "returns the requested subset" do
      @hash.slice(:c, :a).should == { c: 3, a: 1 }
    end

    it "returns a hash ordered in the order of the requested keys" do
      @hash.slice(:c, :a).keys.should == [:c, :a]
    end

    it "returns only the keys of the original hash" do
      @hash.slice(:a, :chunky_bacon).should == { a: 1 }
    end

    it "returns a Hash instance, even on subclasses" do
      klass = Class.new(Hash)
      h = klass.new
      h[:bar] = 12
      h[:foo] = 42
      r = h.slice(:foo)
      r.should == {foo: 42}
      r.class.should == Hash
    end

    it "uses the regular Hash#[] method, even on subclasses that override it" do
      ScratchPad.record []
      klass = Class.new(Hash) do
        def [](value)
          ScratchPad << :used_subclassed_operator
          super
        end
      end

      h = klass.new
      h[:bar] = 12
      h[:foo] = 42
      h.slice(:foo)

      ScratchPad.recorded.should == []
    end
  end
end
