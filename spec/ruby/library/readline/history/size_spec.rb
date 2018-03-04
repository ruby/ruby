require_relative '../spec_helper'

with_feature :readline do
  require_relative 'shared/size'

  describe "Readline::HISTORY.size" do
    it_behaves_like :readline_history_size, :size
  end
end
