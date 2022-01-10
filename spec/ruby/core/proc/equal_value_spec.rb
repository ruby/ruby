require_relative '../../spec_helper'
require_relative 'shared/equal'

describe "Proc#==" do
  ruby_version_is ""..."3.0" do
    it_behaves_like :proc_equal_undefined, :==
  end

  ruby_version_is "3.0" do
    it_behaves_like :proc_equal, :==
  end
end
