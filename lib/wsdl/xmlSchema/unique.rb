=begin
WSDL4R - XMLSchema unique element.
Copyright (C) 2003  NAKAMURA, Hiroshi.

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


require 'wsdl/info'


module WSDL
module XMLSchema


class Unique < Info
  def initialize
    super
  end

  def parse_element(element)
    # Accepts any element.
    self
  end

  def parse_attr(attr, value)
    # Accepts any attribute.
    true
  end
end


end
end
