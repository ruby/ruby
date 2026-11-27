require_relative '../../../spec_helper'

describe "Encoding::Converter::INVALID_MASK" do
  it "exists" do
    Encoding::Converter.should.const_defined?(:INVALID_MASK, false)
  end

  it "has an Integer value" do
    Encoding::Converter::INVALID_MASK.should.instance_of?(Integer)
  end
end

describe "Encoding::Converter::INVALID_REPLACE" do
  it "exists" do
    Encoding::Converter.should.const_defined?(:INVALID_REPLACE, false)
  end

  it "has an Integer value" do
    Encoding::Converter::INVALID_REPLACE.should.instance_of?(Integer)
  end
end

describe "Encoding::Converter::UNDEF_MASK" do
  it "exists" do
    Encoding::Converter.should.const_defined?(:UNDEF_MASK, false)
  end

  it "has an Integer value" do
    Encoding::Converter::UNDEF_MASK.should.instance_of?(Integer)
  end
end

describe "Encoding::Converter::UNDEF_REPLACE" do
  it "exists" do
    Encoding::Converter.should.const_defined?(:UNDEF_REPLACE, false)
  end

  it "has an Integer value" do
    Encoding::Converter::UNDEF_REPLACE.should.instance_of?(Integer)
  end
end

describe "Encoding::Converter::UNDEF_HEX_CHARREF" do
  it "exists" do
    Encoding::Converter.should.const_defined?(:UNDEF_HEX_CHARREF, false)
  end

  it "has an Integer value" do
    Encoding::Converter::UNDEF_HEX_CHARREF.should.instance_of?(Integer)
  end
end

describe "Encoding::Converter::PARTIAL_INPUT" do
  it "exists" do
    Encoding::Converter.should.const_defined?(:PARTIAL_INPUT, false)
  end

  it "has an Integer value" do
    Encoding::Converter::PARTIAL_INPUT.should.instance_of?(Integer)
  end
end

describe "Encoding::Converter::AFTER_OUTPUT" do
  it "exists" do
    Encoding::Converter.should.const_defined?(:AFTER_OUTPUT, false)
  end

  it "has an Integer value" do
    Encoding::Converter::AFTER_OUTPUT.should.instance_of?(Integer)
  end
end

describe "Encoding::Converter::UNIVERSAL_NEWLINE_DECORATOR" do
  it "exists" do
    Encoding::Converter.should.const_defined?(:UNIVERSAL_NEWLINE_DECORATOR, false)
  end

  it "has an Integer value" do
    Encoding::Converter::UNIVERSAL_NEWLINE_DECORATOR.should.instance_of?(Integer)
  end
end

describe "Encoding::Converter::CRLF_NEWLINE_DECORATOR" do
  it "exists" do
    Encoding::Converter.should.const_defined?(:CRLF_NEWLINE_DECORATOR, false)
  end

  it "has an Integer value" do
    Encoding::Converter::CRLF_NEWLINE_DECORATOR.should.instance_of?(Integer)
  end
end

describe "Encoding::Converter::CR_NEWLINE_DECORATOR" do
  it "exists" do
    Encoding::Converter.should.const_defined?(:CR_NEWLINE_DECORATOR, false)
  end

  it "has an Integer value" do
    Encoding::Converter::CR_NEWLINE_DECORATOR.should.instance_of?(Integer)
  end
end

describe "Encoding::Converter::XML_TEXT_DECORATOR" do
  it "exists" do
    Encoding::Converter.should.const_defined?(:XML_TEXT_DECORATOR, false)
  end

  it "has an Integer value" do
    Encoding::Converter::XML_TEXT_DECORATOR.should.instance_of?(Integer)
  end
end

describe "Encoding::Converter::XML_ATTR_CONTENT_DECORATOR" do
  it "exists" do
    Encoding::Converter.should.const_defined?(:XML_ATTR_CONTENT_DECORATOR, false)
  end

  it "has an Integer value" do
    Encoding::Converter::XML_ATTR_CONTENT_DECORATOR.should.instance_of?(Integer)
  end
end

describe "Encoding::Converter::XML_ATTR_QUOTE_DECORATOR" do
  it "exists" do
    Encoding::Converter.should.const_defined?(:XML_ATTR_QUOTE_DECORATOR, false)
  end

  it "has an Integer value" do
    Encoding::Converter::XML_ATTR_QUOTE_DECORATOR.should.instance_of?(Integer)
  end
end
