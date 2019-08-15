require_relative '../../spec_helper'
require_relative 'shared/select'
require_relative 'shared/accessor'
require_relative '../enumerable/shared/enumeratorized'

describe "Struct#select" do
  it_behaves_like :struct_select, :select
  it_behaves_like :struct_accessor, :select
  it_behaves_like :enumeratorized_with_origin_size, :select, Struct.new(:foo).new
end
