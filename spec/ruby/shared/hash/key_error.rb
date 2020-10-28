describe :key_error, shared: true do
  it "raises a KeyError" do
    -> {
      @method.call(@object, 'foo')
    }.should raise_error(KeyError)
  end

  it "sets the Hash as the receiver of KeyError" do
    -> {
      @method.call(@object, 'foo')
    }.should raise_error(KeyError) { |err|
      err.receiver.should equal(@object)
    }
  end

  it "sets the unmatched key as the key of KeyError" do
    -> {
      @method.call(@object, 'foo')
    }.should raise_error(KeyError) { |err|
      err.key.to_s.should == 'foo'
    }
  end
end
