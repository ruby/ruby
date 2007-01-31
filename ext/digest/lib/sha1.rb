# just for compatibility; requiring "sha1" is obsoleted
#
# $RoughId: sha1.rb,v 1.4 2001/07/13 15:38:27 knu Exp $
# $Id: sha1.rb,v 1.1 2001/07/13 20:06:14 knu Exp $

require 'digest/sha1'

SHA1 = Digest::SHA1

class SHA1
  def self.sha1(*args)
    new(*args)
  end
end
