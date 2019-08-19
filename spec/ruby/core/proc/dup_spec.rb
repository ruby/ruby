require_relative '../../spec_helper'
require_relative 'shared/dup'

describe "Proc#dup" do
  it_behaves_like :proc_dup, :dup
end
