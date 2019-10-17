require_relative '../../spec_helper'
require_relative 'shared/then'

ruby_version_is "2.6" do
  describe "Kernel#then" do
    it_behaves_like :kernel_then, :then
  end
end
