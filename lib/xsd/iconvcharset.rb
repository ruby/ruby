# XSD4R - Charset handling with iconv.
# Copyright (C) 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


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
