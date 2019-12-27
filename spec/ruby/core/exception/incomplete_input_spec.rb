require_relative '../../spec_helper'

describe "Encoding::InvalidByteSequenceError#incomplete_input?" do
  -> {"abc\xa4def".encode("ISO-8859-1", "EUC-JP") }.should raise_error(Encoding::InvalidByteSequenceError) { |e|
    e.incomplete_input?.should == false
  }
end
