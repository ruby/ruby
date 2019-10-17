require_relative '../../spec_helper'
require_relative 'shared/select'
require_relative 'shared/accessor'
require_relative '../enumerable/shared/enumeratorized'

ruby_version_is "2.6" do
  describe "Struct#filter" do
    it_behaves_like :struct_select, :filter
    it_behaves_like :struct_accessor, :filter
    it_behaves_like :enumeratorized_with_origin_size, :filter, Struct.new(:foo).new
  end
end
