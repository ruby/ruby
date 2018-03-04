require_relative 'shared/name'

with_feature :encoding do
  describe "Encoding#to_s" do
    it_behaves_like :encoding_name, :to_s
  end
end
