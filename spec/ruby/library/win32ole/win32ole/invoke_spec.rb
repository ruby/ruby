require_relative "../../../spec_helper"
platform_is :windows do
  require_relative '../fixtures/classes'

  describe "WIN32OLE#invoke" do
    before :each do
      @dict = WIN32OLESpecs.new_ole('Scripting.Dictionary')
    end

    it "get value by invoking 'Item' OLE method" do
      @dict.add('key', 'value')
      @dict.invoke('Item', 'key').should == 'value'
    end
  end
end
