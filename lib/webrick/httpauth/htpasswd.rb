#
# httpauth/htpasswd -- Apache compatible htpasswd file
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2003 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: htpasswd.rb,v 1.4 2003/07/22 19:20:45 gotoyuzo Exp $

require 'webrick/httpauth/userdb'
require 'webrick/httpauth/basicauth'
require 'tempfile'

module WEBrick
  module HTTPAuth
    class Htpasswd
      include UserDB

      def initialize(path)
        @path = path
        @mtime = Time.at(0)
        @passwd = Hash.new
        @auth_type = BasicAuth
        open(@path,"a").close unless File::exist?(@path)
        reload
      end

      def reload
        mtime = File::mtime(@path)
        if mtime > @mtime
          @passwd.clear
          open(@path){|io|
            while line = io.gets
              line.chomp!
              user, pass = line.split(":")
              @passwd[user] = pass
            end
          }
          @mtime = mtime
        end
      end

      def flush(output=nil)
        output ||= @path
        tmp = Tempfile.new("htpasswd", File::dirname(output))
        begin
          each{|item| tmp.puts(item.join(":")) }
          tmp.close
          File::rename(tmp.path, output)
        rescue
          tmp.close(true)
        end
      end

      def get_passwd(realm, user, reload_db)
        reload() if reload_db
        @passwd[user]
      end

      def set_passwd(realm, user, pass)
        @passwd[user] = make_passwd(realm, user, pass)
      end

      def delete_passwd(realm, user)
        @passwd.delete(user)
      end

      def each
        @passwd.keys.sort.each{|user|
          yield([user, @passwd[user]])
        }
      end
    end
  end
end
