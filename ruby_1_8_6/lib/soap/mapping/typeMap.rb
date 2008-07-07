# SOAP4R - Base type mapping definition
# Copyright (C) 2000, 2001, 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


module SOAP


TypeMap = {
  XSD::XSDAnySimpleType::Type => SOAPAnySimpleType,
  XSD::XSDString::Type => SOAPString,
  XSD::XSDBoolean::Type => SOAPBoolean,
  XSD::XSDDecimal::Type => SOAPDecimal,
  XSD::XSDFloat::Type => SOAPFloat,
  XSD::XSDDouble::Type => SOAPDouble,
  XSD::XSDDuration::Type => SOAPDuration,
  XSD::XSDDateTime::Type => SOAPDateTime,
  XSD::XSDTime::Type => SOAPTime,
  XSD::XSDDate::Type => SOAPDate,
  XSD::XSDGYearMonth::Type => SOAPGYearMonth,
  XSD::XSDGYear::Type => SOAPGYear,
  XSD::XSDGMonthDay::Type => SOAPGMonthDay,
  XSD::XSDGDay::Type => SOAPGDay,
  XSD::XSDGMonth::Type => SOAPGMonth,
  XSD::XSDHexBinary::Type => SOAPHexBinary,
  XSD::XSDBase64Binary::Type => SOAPBase64,
  XSD::XSDAnyURI::Type => SOAPAnyURI,
  XSD::XSDQName::Type => SOAPQName,
  XSD::XSDInteger::Type => SOAPInteger,
  XSD::XSDNonPositiveInteger::Type => SOAPNonPositiveInteger,
  XSD::XSDNegativeInteger::Type => SOAPNegativeInteger,
  XSD::XSDLong::Type => SOAPLong,
  XSD::XSDInt::Type => SOAPInt,
  XSD::XSDShort::Type => SOAPShort,
  XSD::XSDByte::Type => SOAPByte,
  XSD::XSDNonNegativeInteger::Type => SOAPNonNegativeInteger,
  XSD::XSDUnsignedLong::Type => SOAPUnsignedLong,
  XSD::XSDUnsignedInt::Type => SOAPUnsignedInt,
  XSD::XSDUnsignedShort::Type => SOAPUnsignedShort,
  XSD::XSDUnsignedByte::Type => SOAPUnsignedByte,
  XSD::XSDPositiveInteger::Type => SOAPPositiveInteger,

  SOAP::SOAPBase64::Type => SOAPBase64,
}


end
