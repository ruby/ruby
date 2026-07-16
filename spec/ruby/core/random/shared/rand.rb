describe :random_number, shared: true do
  it "returns a Float if no max argument is passed" do
    @object.send(@method).should.is_a?(Float)
  end

  it "returns an Integer if an Integer argument is passed" do
    @object.send(@method, 20).should.is_a?(Integer)
  end
end
