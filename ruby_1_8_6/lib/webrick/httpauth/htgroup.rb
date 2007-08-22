#
# httpauth/htgroup.rb -- Apache compatible htgroup file
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2003 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: htgroup.rb,v 1.1 2003/02/16 22:22:56 gotoyuzo Exp $

require 'tempfile'

module WEBrick
  module HTTPAuth
    class Htgroup
      def initialize(path)
        @path = path
        @mtime = Time.at(0)
        @group = Hash.new
        open(@path,"a").close unless File::exist?(@path)
        reload
      end

      def reload
        if (mtime = File::mtime(@path)) > @mtime
          @group.clear
          open(@path){|io|
            while line = io.gets
              line.chomp!
              group, members = line.split(/:\s*/)
              @group[group] = members.split(/\s+/)
            end
          }
          @mtime = mtime
        end
      end

      def flush(output=nil)
        output ||= @path
        tmp = Tempfile.new("htgroup", File::dirname(output))
        begin
          @group.keys.sort.each{|group|
            tmp.puts(format("%s: %s", group, self.members(group).join(" ")))
          }
          tmp.close
          File::rename(tmp.path, output)
        rescue
          tmp.close(true)
        end
      end

      def members(group)
        reload
        @group[group] || []
      end

      def add(group, members)
        @group[group] = members(group) | members
      end
    end
  end
end
