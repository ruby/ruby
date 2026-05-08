platform_is :windows do
  require_relative '../../fixtures/classes'

  describe :win32ole_ole_method, shared: true do
    before :each do
      @dict = WIN32OLESpecs.new_ole('Scripting.Dictionary')
    end

    it "raises ArgumentError if no argument is given" do
      -> { @dict.send(@method) }.should.raise ArgumentError
    end

    it "returns the WIN32OLE::Method 'Add' if given 'Add'" do
      result = @dict.send(@method, "Add")
      result.kind_of?(WIN32OLE::Method).should == true
      result.name.should == 'Add'
    end
  end
end
