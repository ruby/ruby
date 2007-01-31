#
# = uri/https.rb
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# License:: You can redistribute it and/or modify it under the same term as Ruby.
# Revision:: $Id: https.rb,v 1.2.2.1 2004/03/24 12:20:32 gsinclair Exp $
#

require 'uri/http'

module URI
  class HTTPS < HTTP
    DEFAULT_PORT = 443
  end
  @@schemes['HTTPS'] = HTTPS
end
