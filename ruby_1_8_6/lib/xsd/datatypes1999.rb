# XSD4R - XML Schema Datatype 1999 support
# Copyright (C) 2001, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/datatypes'


module XSD
  Namespace.replace('http://www.w3.org/1999/XMLSchema')
  InstanceNamespace.replace('http://www.w3.org/1999/XMLSchema-instance')
  AnyTypeLiteral.replace('ur-type')
  AnySimpleTypeLiteral.replace('ur-type')
  NilLiteral.replace('null')
  NilValue.replace('1')
  DateTimeLiteral.replace('timeInstant')
end
