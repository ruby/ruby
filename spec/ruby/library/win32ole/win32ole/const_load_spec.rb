require_relative "../../../spec_helper"
platform_is :windows do
  require_relative '../fixtures/classes'

  describe "WIN32OLE.const_load when passed Shell.Application OLE object" do
    before :each do
      @win32ole = WIN32OLESpecs.new_ole 'Shell.Application'
    end

    it "loads constant SsfWINDOWS into WIN32OLE namespace" do
      WIN32OLE.const_defined?(:SsfWINDOWS).should be_false
      WIN32OLE.const_load @win32ole
      WIN32OLE.const_defined?(:SsfWINDOWS).should be_true
    end
  end

  describe "WIN32OLE.const_load when namespace is specified" do
    before :each do
      module WIN32OLE_RUBYSPEC; end
      @win32ole = WIN32OLESpecs.new_ole 'Shell.Application'
    end

    it "loads constants into given namespace" do
      module WIN32OLE_RUBYSPEC; end

      WIN32OLE_RUBYSPEC.const_defined?(:SsfWINDOWS).should be_false
      WIN32OLE.const_load @win32ole, WIN32OLE_RUBYSPEC
      WIN32OLE_RUBYSPEC.const_defined?(:SsfWINDOWS).should be_true

    end
  end

end
