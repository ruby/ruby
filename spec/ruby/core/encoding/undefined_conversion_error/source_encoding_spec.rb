require_relative '../fixtures/classes'

describe "Encoding::UndefinedConversionError#source_encoding" do
  before :each do
    @exception = EncodingSpecs::UndefinedConversionError.exception
    @exception2 = EncodingSpecs::UndefinedConversionErrorIndirect.exception
  end

  it "returns an Encoding object" do
    @exception.source_encoding.should be_an_instance_of(Encoding)
    @exception2.source_encoding.should be_an_instance_of(Encoding)
  end

  it "is equal to the source encoding of the object that raised it" do
    @exception.source_encoding.should == Encoding::UTF_8
  end

  # The source encoding specified in the Encoding::Converter constructor may
  # differ from the source encoding returned here. What seems to happen is
  # that when transcoding along a path with multiple pairs of encodings, the
  # last one encountered when the error occurred is returned. So in this
  # case, the conversion path is ISO-8859-1 -> UTF-8 -> EUC-JP. The
  # conversion from ISO-8859-1 -> UTF-8 succeeded, but the conversion from
  # UTF-8 to EUC-JP failed. IOW, it failed when the source encoding was
  # UTF-8, so UTF-8 is regarded as the source encoding.
  it "is equal to the source encoding at the stage of the conversion path where the error occurred" do
    @exception2.source_encoding.should == Encoding::UTF_8
  end
end
