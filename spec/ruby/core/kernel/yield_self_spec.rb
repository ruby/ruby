require_relative '../../spec_helper'
require_relative 'shared/then'

ruby_version_is "2.5" do
  describe "Kernel#yield_self" do
    it_behaves_like :kernel_then, :yield_self
  end
end
