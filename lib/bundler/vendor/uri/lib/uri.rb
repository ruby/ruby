# frozen_string_literal: false
# Bundler::URI is a module providing classes to handle Uniform Resource Identifiers
# (RFC2396[https://www.rfc-editor.org/rfc/rfc2396]).
#
# == Features
#
# * Uniform way of handling URIs.
# * Flexibility to introduce custom Bundler::URI schemes.
# * Flexibility to have an alternate Bundler::URI::Parser (or just different patterns
#   and regexp's).
#
# == Basic example
#
#   require 'bundler/vendor/uri/lib/uri'
#
#   uri = Bundler::URI("http://foo.com/posts?id=30&limit=5#time=1305298413")
#   #=> #<Bundler::URI::HTTP http://foo.com/posts?id=30&limit=5#time=1305298413>
#
#   uri.scheme    #=> "http"
#   uri.host      #=> "foo.com"
#   uri.path      #=> "/posts"
#   uri.query     #=> "id=30&limit=5"
#   uri.fragment  #=> "time=1305298413"
#
#   uri.to_s      #=> "http://foo.com/posts?id=30&limit=5#time=1305298413"
#
# == Adding custom URIs
#
#   module Bundler::URI
#     class RSYNC < Generic
#       DEFAULT_PORT = 873
#     end
#     register_scheme 'RSYNC', RSYNC
#   end
#   #=> Bundler::URI::RSYNC
#
#   Bundler::URI.scheme_list
#   #=> {"FILE"=>Bundler::URI::File, "FTP"=>Bundler::URI::FTP, "HTTP"=>Bundler::URI::HTTP,
#   #    "HTTPS"=>Bundler::URI::HTTPS, "LDAP"=>Bundler::URI::LDAP, "LDAPS"=>Bundler::URI::LDAPS,
#   #    "MAILTO"=>Bundler::URI::MailTo, "RSYNC"=>Bundler::URI::RSYNC}
#
#   uri = Bundler::URI("rsync://rsync.foo.com")
#   #=> #<Bundler::URI::RSYNC rsync://rsync.foo.com>
#
# == RFC References
#
# A good place to view an RFC spec is http://www.ietf.org/rfc.html.
#
# Here is a list of all related RFC's:
# - RFC822[https://www.rfc-editor.org/rfc/rfc822]
# - RFC1738[https://www.rfc-editor.org/rfc/rfc1738]
# - RFC2255[https://www.rfc-editor.org/rfc/rfc2255]
# - RFC2368[https://www.rfc-editor.org/rfc/rfc2368]
# - RFC2373[https://www.rfc-editor.org/rfc/rfc2373]
# - RFC2396[https://www.rfc-editor.org/rfc/rfc2396]
# - RFC2732[https://www.rfc-editor.org/rfc/rfc2732]
# - RFC3986[https://www.rfc-editor.org/rfc/rfc3986]
#
# == Class tree
#
# - Bundler::URI::Generic (in uri/generic.rb)
#   - Bundler::URI::File - (in uri/file.rb)
#   - Bundler::URI::FTP - (in uri/ftp.rb)
#   - Bundler::URI::HTTP - (in uri/http.rb)
#     - Bundler::URI::HTTPS - (in uri/https.rb)
#   - Bundler::URI::LDAP - (in uri/ldap.rb)
#     - Bundler::URI::LDAPS - (in uri/ldaps.rb)
#   - Bundler::URI::MailTo - (in uri/mailto.rb)
# - Bundler::URI::Parser - (in uri/common.rb)
# - Bundler::URI::REGEXP - (in uri/common.rb)
#   - Bundler::URI::REGEXP::PATTERN - (in uri/common.rb)
# - Bundler::URI::Util - (in uri/common.rb)
# - Bundler::URI::Error - (in uri/common.rb)
#   - Bundler::URI::InvalidURIError - (in uri/common.rb)
#   - Bundler::URI::InvalidComponentError - (in uri/common.rb)
#   - Bundler::URI::BadURIError - (in uri/common.rb)
#
# == Copyright Info
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# Documentation::
#   Akira Yamada <akira@ruby-lang.org>
#   Dmitry V. Sabanin <sdmitry@lrn.ru>
#   Vincent Batts <vbatts@hashbangbash.com>
# License::
#  Copyright (c) 2001 akira yamada <akira@ruby-lang.org>
#  You can redistribute it and/or modify it under the same term as Ruby.
#

module Bundler::URI
end

require_relative 'uri/version'
require_relative 'uri/common'
require_relative 'uri/generic'
require_relative 'uri/file'
require_relative 'uri/ftp'
require_relative 'uri/http'
require_relative 'uri/https'
require_relative 'uri/ldap'
require_relative 'uri/ldaps'
require_relative 'uri/mailto'
require_relative 'uri/ws'
require_relative 'uri/wss'
