require_relative '../../spec_helper'
require_relative 'shared/to_s'

describe "Proc#to_s" do
  it_behaves_like :proc_to_s, :to_s
end
