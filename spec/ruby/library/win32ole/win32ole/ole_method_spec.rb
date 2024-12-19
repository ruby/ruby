require_relative "../../../spec_helper"
platform_is :windows do
  verbose, $VERBOSE = $VERBOSE, nil

  require_relative '../fixtures/classes'
  require_relative 'shared/ole_method'

  describe "WIN32OLE#ole_method" do
    it_behaves_like :win32ole_ole_method, :ole_method

  end

ensure
  $VERBOSE = verbose
end
