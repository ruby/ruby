#
# httpauth/htdigest.rb -- Apache compatible htdigest file
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2003 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: htdigest.rb,v 1.4 2003/07/22 19:20:45 gotoyuzo Exp $

require 'webrick/httpauth/userdb'
require 'webrick/httpauth/digestauth'
require 'tempfile'

module WEBrick
  module HTTPAuth
    class Htdigest
      include UserDB

      def initialize(path)
        @path = path
        @mtime = Time.at(0)
        @digest = Hash.new
        @mutex = Mutex::new
        @auth_type = DigestAuth
        open(@path,"a").close unless File::exist?(@path)
        reload
      end

      def reload
        mtime = File::mtime(@path)
        if mtime > @mtime
          @digest.clear
          open(@path){|io|
            while line = io.gets
              line.chomp!
              user, realm, pass = line.split(/:/, 3)
              unless @digest[realm]
                @digest[realm] = Hash.new
              end
              @digest[realm][user] = pass
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
        if hash = @digest[realm]
          hash[user]
        end
      end

      def set_passwd(realm, user, pass)
        @mutex.synchronize{
          unless @digest[realm]
            @digest[realm] = Hash.new
          end
          @digest[realm][user] = make_passwd(realm, user, pass)
        }
      end

      def delete_passwd(realm, user)
        if hash = @digest[realm]
          hash.delete(user)
        end
      end

      def each
        @digest.keys.sort.each{|realm|
          hash = @digest[realm]
          hash.keys.sort.each{|user|
            yield([user, realm, hash[user]])
          }
        }
      end
    end
  end
end
