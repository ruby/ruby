describe :delete_if, shared: true do
  before :each do
    @object = [1,2,3]
  end

  it "updates the receiver after all blocks" do
    @object.send(@method) do |e|
      @object.length.should == 3
      true
    end
    @object.length.should == 0
  end
end
