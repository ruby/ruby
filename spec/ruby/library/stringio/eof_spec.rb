require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/eof'

describe "StringIO#eof?" do
  it_behaves_like :stringio_eof, :eof?
end

describe "StringIO#eof" do
  it_behaves_like :stringio_eof, :eof
end
