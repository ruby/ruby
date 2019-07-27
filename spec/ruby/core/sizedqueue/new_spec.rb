require_relative '../../spec_helper'
require_relative '../../shared/sizedqueue/new'

describe "SizedQueue.new" do
  it_behaves_like :sizedqueue_new, :new, -> *n { SizedQueue.new(*n) }
end
