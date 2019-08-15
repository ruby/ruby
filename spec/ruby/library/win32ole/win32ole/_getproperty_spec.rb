platform_is :windows do
  require_relative '../fixtures/classes'

  describe "WIN32OLE#_getproperty" do
    before :each do
      @dict = WIN32OLESpecs.new_ole('Scripting.Dictionary')
    end

    it "gets value" do
      @dict.add('key', 'value')
      @dict._getproperty(0, ['key'], [WIN32OLE::VARIANT::VT_BSTR]).should == 'value'
    end
  end
end
