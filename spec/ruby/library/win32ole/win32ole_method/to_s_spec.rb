require_relative "../../../spec_helper"
require_relative 'shared/name'

platform_is :windows do
  require 'win32ole'

  describe "WIN32OLE::Method#name" do
    it_behaves_like :win32ole_method_name, :to_s

  end

end
