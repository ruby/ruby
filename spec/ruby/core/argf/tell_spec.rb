require_relative '../../spec_helper'
require_relative 'shared/pos'

describe "ARGF.tell" do
  it_behaves_like :argf_pos, :tell
end
