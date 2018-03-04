require_relative 'shared/name'

with_feature :encoding do
  describe "Encoding#name" do
    it_behaves_like :encoding_name, :name
  end
end
