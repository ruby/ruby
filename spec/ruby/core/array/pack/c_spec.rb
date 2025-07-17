# encoding: binary

require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'
require_relative 'shared/numeric_basic'

describe :array_pack_8bit, shared: true do
  it "encodes the least significant eight bits of a positive number" do
    [ [[49],           "1"],
      [[0b11111111],   "\xFF"],
      [[0b100000000],  "\x00"],
      [[0b100000001],  "\x01"]
    ].should be_computed_by(:pack, pack_format)
  end

  it "encodes the least significant eight bits of a negative number" do
    [ [[-1],           "\xFF"],
      [[-0b10000000],  "\x80"],
      [[-0b11111111],  "\x01"],
      [[-0b100000000], "\x00"],
      [[-0b100000001], "\xFF"]
    ].should be_computed_by(:pack, pack_format)
  end

  it "encodes a Float truncated as an Integer" do
    [ [[5.2], "\x05"],
      [[5.8], "\x05"]
    ].should be_computed_by(:pack, pack_format)
  end

  it "calls #to_int to convert the pack argument to an Integer" do
    obj = mock('to_int')
    obj.should_receive(:to_int).and_return(5)
    [obj].pack(pack_format).should == "\x05"
  end

  it "encodes the number of array elements specified by the count modifier" do
    [ [[1, 2, 3], pack_format(3), "\x01\x02\x03"],
      [[1, 2, 3], pack_format(2) + pack_format(1), "\x01\x02\x03"]
    ].should be_computed_by(:pack)
  end

  it "encodes all remaining elements when passed the '*' modifier" do
    [1, 2, 3, 4, 5].pack(pack_format('*')).should == "\x01\x02\x03\x04\x05"
  end

  ruby_version_is ""..."3.3" do
    it "ignores NULL bytes between directives" do
      suppress_warning do
        [1, 2, 3].pack(pack_format("\000", 2)).should == "\x01\x02"
      end
    end
  end

  ruby_version_is "3.3" do
    it "raise ArgumentError for NULL bytes between directives" do
      -> {
        [1, 2, 3].pack(pack_format("\000", 2))
      }.should raise_error(ArgumentError, /unknown pack directive/)
    end
  end

  it "ignores spaces between directives" do
    [1, 2, 3].pack(pack_format(' ', 2)).should == "\x01\x02"
  end
end

describe "Array#pack with format 'C'" do
  it_behaves_like :array_pack_basic, 'C'
  it_behaves_like :array_pack_basic_non_float, 'C'
  it_behaves_like :array_pack_8bit, 'C'
  it_behaves_like :array_pack_arguments, 'C'
  it_behaves_like :array_pack_numeric_basic, 'C'
  it_behaves_like :array_pack_integer, 'C'
  it_behaves_like :array_pack_no_platform, 'C'
end

describe "Array#pack with format 'c'" do
  it_behaves_like :array_pack_basic, 'c'
  it_behaves_like :array_pack_basic_non_float, 'c'
  it_behaves_like :array_pack_8bit, 'c'
  it_behaves_like :array_pack_arguments, 'c'
  it_behaves_like :array_pack_numeric_basic, 'c'
  it_behaves_like :array_pack_integer, 'c'
  it_behaves_like :array_pack_no_platform, 'c'
end
