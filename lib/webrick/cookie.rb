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
require 'webrick/httputils'

module WEBrick
  class Cookie

    attr_reader :name
    attr_accessor :value, :version
    attr_accessor :domain, :path, :secure
    attr_accessor :comment, :max_age
    #attr_accessor :comment_url, :discard, :port

    def initialize(name, value)
      @name = name
      @value = value
      @version = 0     # Netscape Cookie

      @domain = @path = @secure = @comment = @max_age =
      @expires = @comment_url = @discard = @port = nil
    end

    def expires=(t)
      @expires = t && (t.is_a?(Time) ? t.httpdate : t.to_s)
    end

    def expires
      @expires && Time.parse(@expires)
    end

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

    # Cookie::parse()
    #   It parses Cookie field sent from the user agent.
    def self.parse(str)
      if str
        ret = []
        cookie = nil
        ver = 0
        str.split(/[;,]\s+/).each{|x|
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

  end
end
