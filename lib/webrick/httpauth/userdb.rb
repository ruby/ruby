#
# httpauth/userdb.rb -- UserDB mix-in module.
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2003 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: userdb.rb,v 1.2 2003/02/20 07:15:48 gotoyuzo Exp $

module WEBrick
  module HTTPAuth
    module UserDB
      attr_accessor :auth_type # BasicAuth or DigestAuth

      def make_passwd(realm, user, pass)
        @auth_type::make_passwd(realm, user, pass)
      end

      def set_passwd(realm, user, pass)
        self[user] = pass
      end

      def get_passwd(realm, user, reload_db=false)
        # reload_db is dummy
        make_passwd(realm, user, self[user])
      end
    end
  end
end
