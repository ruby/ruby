# just for compatibility; requiring "sha1" is obsoleted
#
# $RoughId: sha1.rb,v 1.4 2001/07/13 15:38:27 knu Exp $
# $Id$

require 'digest/sha1'

class SHA1 < Digest::SHA1
  class << self
    alias orig_new new
    def new(str = nil)
      if str
        orig_new.update(str)
      else
        orig_new
      end
    end

    def sha1(*args)
      new(*args)
    end
  end
end
