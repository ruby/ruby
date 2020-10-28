describe :random_number, shared: true do
  it "returns a Float if no max argument is passed" do
    @object.send(@method).should be_kind_of(Float)
  end

  it "returns an Integer if an Integer argument is passed" do
    @object.send(@method, 20).should be_kind_of(Integer)
  end
end
