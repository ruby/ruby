require_relative '../fixtures/classes'
require_relative 'shared/setproperty'

platform_is :windows do
  require 'win32ole'

  describe "WIN32OLE#setproperty" do
    it_behaves_like :win32ole_setproperty, :setproperty

  end

end
