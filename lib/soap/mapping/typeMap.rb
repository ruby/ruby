=begin
SOAP4R - Base type mapping definition
Copyright (C) 2000, 2001, 2002, 2003  NAKAMURA, Hiroshi.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PRATICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 675 Mass
Ave, Cambridge, MA 02139, USA.
=end


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
  XSD::XSDLong::Type => SOAPLong,
  XSD::XSDInt::Type => SOAPInt,
  XSD::XSDShort::Type => SOAPShort,

  SOAP::SOAPBase64::Type => SOAPBase64,
}


end
