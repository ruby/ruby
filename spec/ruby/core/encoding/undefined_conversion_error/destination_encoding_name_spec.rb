require_relative '../fixtures/classes'

describe "Encoding::UndefinedConversionError#destination_encoding_name" do
  before :each do
    @exception = EncodingSpecs::UndefinedConversionError.exception
  end

  it "returns a String" do
    @exception.destination_encoding_name.should be_an_instance_of(String)
  end

  it "is equal to the destination encoding name of the object that raised it" do
    @exception.destination_encoding_name.should == "US-ASCII"
  end
end
