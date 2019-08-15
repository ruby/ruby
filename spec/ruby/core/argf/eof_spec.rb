require_relative '../../spec_helper'
require_relative 'shared/eof'

describe "ARGF.eof" do
  it_behaves_like :argf_eof, :eof
end

describe "ARGF.eof?" do
  it_behaves_like :argf_eof, :eof?
end
