=begin
XSD4R - XML Schema Datatype 1999 support
Copyright (C) 2001, 2003  NAKAMURA, Hiroshi.

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
