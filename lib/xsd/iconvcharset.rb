=begin
XSD4R - Charset handling with iconv.
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


require 'iconv'


module XSD


class IconvCharset
  def self.safe_iconv(to, from, str)
    iconv = Iconv.new(to, from)
    out = ""
    begin
      out << iconv.iconv(str)
    rescue Iconv::IllegalSequence => e
      out << e.success
      ch, str = e.failed.split(//, 2)
      out << '?'
      STDERR.puts("Failed to convert #{ch}")
      retry
    end
    return out
  end
end


end
