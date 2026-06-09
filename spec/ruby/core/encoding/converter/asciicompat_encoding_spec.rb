require_relative '../../../spec_helper'

describe "Encoding::Converter.asciicompat_encoding" do
  it "coerces non-String/Encoding objects with #to_str" do
    str = mock('string')
    str.should_receive(:to_str).at_least(1).times.and_return('string')
    Encoding::Converter.asciicompat_encoding(str)
  end

  it "accepts an Encoding object as an argument" do
    Encoding::Converter.asciicompat_encoding(Encoding.find("ISO-2022-JP")).should ==
      Encoding::Converter.asciicompat_encoding("ISO-2022-JP")
  end

  it "returns a corresponding ASCII compatible encoding for ASCII-incompatible encodings" do
    Encoding::Converter.asciicompat_encoding('UTF-16BE').should == Encoding::UTF_8
    Encoding::Converter.asciicompat_encoding("ISO-2022-JP").should == Encoding.find("stateless-ISO-2022-JP")
  end

  it "returns nil when the given encoding is ASCII compatible" do
    Encoding::Converter.asciicompat_encoding('ASCII').should == nil
    Encoding::Converter.asciicompat_encoding('UTF-8').should == nil
  end

  it "handles encoding names who resolve to nil encodings" do
    internal = Encoding.default_internal
    Encoding.default_internal = nil
    Encoding::Converter.asciicompat_encoding('internal').should == nil
    Encoding.default_internal = internal
  end
end
