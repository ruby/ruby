require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../fixtures/classes', __FILE__)
require File.expand_path('../shared/call', __FILE__)

ruby_version_is "2.5" do
  describe "Method#===" do
    it_behaves_like :method_call, :===
  end
end
