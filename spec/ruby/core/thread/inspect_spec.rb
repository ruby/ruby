require_relative '../../spec_helper'
require_relative 'shared/to_s'

describe "Thread#inspect" do
  it_behaves_like :thread_to_s, :inspect
end
