describe :enumeratorize, shared: true do
  it "returns an Enumerator if no block given" do
    [1,2].send(@method).should.instance_of?(Enumerator)
  end
end
