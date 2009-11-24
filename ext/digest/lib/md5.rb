# just for compatibility; requiring "md5" is obsoleted
#
# $RoughId: md5.rb,v 1.4 2001/07/13 15:38:27 knu Exp $
# $Id$

warn "require 'md5' is obsolete; require 'digest' and use Digest::MD5." if $VERBOSE

require 'digest/md5'

class MD5 < Digest::MD5
  class << self
    alias orig_new new
    def new(str = nil)
      if str
        orig_new.update(str)
      else
        orig_new
      end
    end

    def md5(*args)
      new(*args)
    end
  end
end
