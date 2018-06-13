require_relative '../../spec_helper'

ruby_version_is '2.4' do
  describe "Integer#dup" do
    it "returns self for small integers" do
      integer = 1_000
      integer.dup.should equal(integer)
    end

    it "returns self for large integers" do
      integer = 4_611_686_018_427_387_905
      integer.dup.should equal(integer)
    end
  end
end
