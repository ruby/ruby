#
# httpauth/basicauth.rb -- HTTP basic access authentication
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2003 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: basicauth.rb,v 1.5 2003/02/20 07:15:47 gotoyuzo Exp $

require 'webrick/config'
require 'webrick/httpstatus'
require 'webrick/httpauth/authenticator'

module WEBrick
  module HTTPAuth
    class BasicAuth
      include Authenticator

      AuthScheme = "Basic"

      def self.make_passwd(realm, user, pass)
        pass ||= ""
        pass.crypt(Utils::random_string(2))
      end

      attr_reader :realm, :userdb, :logger

      def initialize(config, default=Config::BasicAuth)
        check_init(config)
        @config = default.dup.update(config)
      end

      def authenticate(req, res)
        unless basic_credentials = check_scheme(req)
          challenge(req, res)
        end
        userid, password = decode64(basic_credentials).split(":", 2) 
        password ||= ""
        if userid.empty?
          error("user id was not given.")
          challenge(req, res)
        end
        unless encpass = @userdb.get_passwd(@realm, userid, @reload_db)
          error("%s: the user is not allowed.", userid)
          challenge(req, res)
        end
        if password.crypt(encpass) != encpass
          error("%s: password unmatch.", userid)
          challenge(req, res)
        end
        info("%s: authentication succeeded.", userid)
        req.user = userid
      end

      def challenge(req, res)
        res[@response_field] = "#{@auth_scheme} realm=\"#{@realm}\""
        raise @auth_exception
      end
    end

    class ProxyBasicAuth < BasicAuth
      include ProxyAuthenticator
    end
  end
end
