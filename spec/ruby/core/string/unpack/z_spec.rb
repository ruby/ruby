# -*- encoding: ascii-8bit -*-
require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'
require_relative 'shared/string'
require_relative 'shared/taint'

describe "String#unpack with format 'Z'" do
  it_behaves_like :string_unpack_basic, 'Z'
  it_behaves_like :string_unpack_no_platform, 'Z'
  it_behaves_like :string_unpack_string, 'Z'
  it_behaves_like :string_unpack_taint, 'Z'

  it "stops decoding at NULL bytes when passed the '*' modifier" do
    "a\x00\x00 b \x00c".unpack('Z*Z*Z*Z*').should == ["a", "", " b ", "c"]
  end

  it "decodes the number of bytes specified by the count modifier and truncates the decoded string at the first NULL byte" do
    [ ["a\x00 \x00b c",      ["a", " "]],
      ["\x00a\x00 bc \x00",  ["", "c"]]
    ].should be_computed_by(:unpack, "Z5Z")
  end
end
