describe :set_include, shared: true do
  it "returns true when self contains the passed Object" do
    set = Set[:a, :b, :c]
    set.send(@method, :a).should be_true
    set.send(@method, :e).should be_false
  end

  describe "member equality" do
    it "is checked using both #hash and #eql?" do
      obj = Object.new
      obj_another = Object.new

      def obj.hash; 42 end
      def obj_another.hash; 42 end
      def obj_another.eql?(o) hash == o.hash end

      set = Set["a", "b", "c", obj]
      set.send(@method, obj_another).should == true
    end

    it "is not checked using #==" do
      obj = Object.new
      set = Set["a", "b", "c"]

      obj.should_not_receive(:==)
      set.send(@method, obj)
    end
  end
end
