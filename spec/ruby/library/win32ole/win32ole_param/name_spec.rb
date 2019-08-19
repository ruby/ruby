require_relative 'shared/name'

platform_is :windows do
  require 'win32ole'

  describe "WIN32OLE_PARAM#name" do
    it_behaves_like :win32ole_param_name, :name

  end

end
