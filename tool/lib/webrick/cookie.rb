# frozen_string_literal: false
#
# cookie.rb -- Cookie class
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2000, 2001 TAKAHASHI Masayoshi, GOTOU Yuuzou
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: cookie.rb,v 1.16 2002/09/21 12:23:35 gotoyuzo Exp $

require 'time'
require_relative 'httputils'

module WEBrick

  ##
  # Processes HTTP cookies

  class Cookie

    ##
    # The cookie name

    attr_reader :name

    ##
    # The cookie value

    attr_accessor :value

    ##
    # The cookie version

    attr_accessor :version

    ##
    # The cookie domain
    attr_accessor :domain

    ##
    # The cookie path

    attr_accessor :path

    ##
    # Is this a secure cookie?

    attr_accessor :secure

    ##
    # The cookie comment

    attr_accessor :comment

    ##
    # The maximum age of the cookie

    attr_accessor :max_age

    #attr_accessor :comment_url, :discard, :port

    ##
    # Creates a new cookie with the given +name+ and +value+

    def initialize(name, value)
      @name = name
      @value = value
      @version = 0     # Netscape Cookie

      @domain = @path = @secure = @comment = @max_age =
      @expires = @comment_url = @discard = @port = nil
    end

    ##
    # Sets the cookie expiration to the time +t+.  The expiration time may be
    # a false value to disable expiration or a Time or HTTP format time string
    # to set the expiration date.

    def expires=(t)
      @expires = t && (t.is_a?(Time) ? t.httpdate : t.to_s)
    end

    ##
    # Retrieves the expiration time as a Time

    def expires
      @expires && Time.parse(@expires)
    end

    ##
    # The cookie string suitable for use in an HTTP header

    def to_s
      ret = ""
      ret << @name << "=" << @value
      ret << "; " << "Version=" << @version.to_s if @version > 0
      ret << "; " << "Domain="  << @domain  if @domain
      ret << "; " << "Expires=" << @expires if @expires
      ret << "; " << "Max-Age=" << @max_age.to_s if @max_age
      ret << "; " << "Comment=" << @comment if @comment
      ret << "; " << "Path="    << @path if @path
      ret << "; " << "Secure"   if @secure
      ret
    end

    ##
    # Parses a Cookie field sent from the user-agent.  Returns an array of
    # cookies.

    def self.parse(str)
      if str
        ret = []
        cookie = nil
        ver = 0
        str.split(/;\s+/).each{|x|
          key, val = x.split(/=/,2)
          val = val ? HTTPUtils::dequote(val) : ""
          case key
          when "$Version"; ver = val.to_i
          when "$Path";    cookie.path = val
          when "$Domain";  cookie.domain = val
          when "$Port";    cookie.port = val
          else
            ret << cookie if cookie
            cookie = self.new(key, val)
            cookie.version = ver
          end
        }
        ret << cookie if cookie
        ret
      end
    end

    ##
    # Parses the cookie in +str+

    def self.parse_set_cookie(str)
      cookie_elem = str.split(/;/)
      first_elem = cookie_elem.shift
      first_elem.strip!
      key, value = first_elem.split(/=/, 2)
      cookie = new(key, HTTPUtils.dequote(value))
      cookie_elem.each{|pair|
        pair.strip!
        key, value = pair.split(/=/, 2)
        if value
          value = HTTPUtils.dequote(value.strip)
        end
        case key.downcase
        when "domain"  then cookie.domain  = value
        when "path"    then cookie.path    = value
        when "expires" then cookie.expires = value
        when "max-age" then cookie.max_age = Integer(value)
        when "comment" then cookie.comment = value
        when "version" then cookie.version = Integer(value)
        when "secure"  then cookie.secure = true
        end
      }
      return cookie
    end

    ##
    # Parses the cookies in +str+

    def self.parse_set_cookies(str)
      return str.split(/,(?=[^;,]*=)|,$/).collect{|c|
        parse_set_cookie(c)
      }
    end
  end
end
