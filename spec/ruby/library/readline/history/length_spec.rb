require_relative '../spec_helper'

with_feature :readline do
  require_relative 'shared/size'

  describe "Readline::HISTORY.length" do
    it_behaves_like :readline_history_size, :length
  end
end
