require_relative "../../../spec_helper"
platform_is :windows do
  verbose, $VERBOSE = $VERBOSE, nil

  require_relative '../fixtures/classes'
  require_relative 'shared/setproperty'

  describe "WIN32OLE#setproperty" do
    it_behaves_like :win32ole_setproperty, :setproperty

  end

ensure
  $VERBOSE = verbose
end
