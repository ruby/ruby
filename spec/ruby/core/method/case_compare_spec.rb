require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/call'

ruby_version_is "2.5" do
  describe "Method#===" do
    it_behaves_like :method_call, :===
  end
end
