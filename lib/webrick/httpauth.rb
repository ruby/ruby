#
# httpauth.rb -- HTTP access authentication
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2000, 2001 TAKAHASHI Masayoshi, GOTOU Yuuzou
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: httpauth.rb,v 1.14 2003/07/22 19:20:42 gotoyuzo Exp $

require 'webrick/httpauth/basicauth'
require 'webrick/httpauth/digestauth'
require 'webrick/httpauth/htpasswd'
require 'webrick/httpauth/htdigest'
require 'webrick/httpauth/htgroup'

module WEBrick
  module HTTPAuth
    module_function

    def _basic_auth(req, res, realm, req_field, res_field, err_type, block)
      user = pass = nil
      if /^Basic\s+(.*)/o =~ req[req_field]
        userpass = $1
        user, pass = decode64(userpass).split(":", 2)
      end
      if block.call(user, pass)
        req.user = user
        return
      end
      res[res_field] = "Basic realm=\"#{realm}\""
      raise err_type
    end

    def basic_auth(req, res, realm, &block)
      _basic_auth(req, res, realm, "Authorization", "WWW-Authenticate",
                  HTTPStatus::Unauthorized, block)
    end

    def proxy_basic_auth(req, res, realm, &block)
      _basic_auth(req, res, realm, "Proxy-Authorization", "Proxy-Authenticate",
                  HTTPStatus::ProxyAuthenticationRequired, block)
    end
  end
end
