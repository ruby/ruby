require File.expand_path('../../../spec_helper', __FILE__)

ruby_version_is '2.4' do
  describe "Symbol#dup" do
    it "returns self" do
      :a_symbol.dup.should equal(:a_symbol)
    end
  end
end
