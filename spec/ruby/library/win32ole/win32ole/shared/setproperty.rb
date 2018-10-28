platform_is :windows do
  require_relative '../../fixtures/classes'

  describe :win32ole_setproperty, shared: true do
    before :each do
      @dict = WIN32OLESpecs.new_ole('Scripting.Dictionary')
    end

    it "raises ArgumentError if no argument is given" do
      lambda { @dict.send(@method) }.should raise_error ArgumentError
    end

    it "sets key to newkey and returns nil" do
      oldkey = 'oldkey'
      newkey = 'newkey'
      @dict.add(oldkey, 'value')
      result = @dict.send(@method, 'Key', oldkey, newkey)
      result.should == nil
      @dict[oldkey].should == nil
      @dict[newkey].should == 'value'
    end
  end
end
