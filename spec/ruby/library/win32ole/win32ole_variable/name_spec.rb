require_relative "../../../spec_helper"
require_relative 'shared/name'

platform_is :windows do
  verbose, $VERBOSE = $VERBOSE, nil

  require 'win32ole'

  describe "WIN32OLE_VARIABLE#name" do
    it_behaves_like :win32ole_variable_new, :name

  end

ensure
  $VERBOSE = verbose
end
