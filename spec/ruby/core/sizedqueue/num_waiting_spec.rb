require_relative '../../spec_helper'
require_relative '../../shared/sizedqueue/num_waiting'

describe "SizedQueue#num_waiting" do
  it_behaves_like :sizedqueue_num_waiting, :new, -> n { SizedQueue.new(n) }
end
