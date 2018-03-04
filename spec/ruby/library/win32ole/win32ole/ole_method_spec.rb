require_relative '../fixtures/classes'
require_relative 'shared/ole_method'

platform_is :windows do
  require 'win32ole'

  describe "WIN32OLE#ole_method" do
    it_behaves_like :win32ole_ole_method, :ole_method

  end

end
