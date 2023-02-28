require_relative "../../../spec_helper"
require_relative 'shared/name'

platform_is :windows do
  require 'win32ole'

  describe "WIN32OLE_VARIABLE#to_s" do
    it_behaves_like :win32ole_variable_new, :to_s

  end

end
