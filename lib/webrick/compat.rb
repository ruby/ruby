#
# compat.rb -- cross platform compatibility
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2002 GOTOU Yuuzou
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: compat.rb,v 1.6 2002/10/01 17:16:32 gotoyuzo Exp $

module Errno
  class EPROTO       < SystemCallError; end
  class ECONNRESET   < SystemCallError; end
  class ECONNABORTED < SystemCallError; end
end

unless File.respond_to?(:fnmatch)
  def File.fnmatch(pat, str)
    case pat[0]
    when nil
      not str[0]
    when ?*
      fnmatch(pat[1..-1], str) || str[0] && fnmatch(pat, str[1..-1])
    when ??
      str[0] && fnmatch(pat[1..-1], str[1..-1])
    else
      pat[0] == str[0] && fnmatch(pat[1..-1], str[1..-1])
    end
  end
end
