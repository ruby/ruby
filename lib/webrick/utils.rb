#
# utils.rb -- Miscellaneous utilities
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2001 TAKAHASHI Masayoshi, GOTOU Yuuzou
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: utils.rb,v 1.10 2003/02/16 22:22:54 gotoyuzo Exp $

require 'socket'
require 'fcntl'
begin
  require 'etc'
rescue LoadError
  nil
end

module WEBrick
  module Utils

    def set_close_on_exec(io)
      if defined?(Fcntl::FD_CLOEXEC)
        io.fcntl(Fcntl::FD_CLOEXEC, 1)
      end
    end
    module_function :set_close_on_exec

    def su(user, group=nil)
      if defined?(Etc)
        pw = Etc.getpwnam(user)
        gr = group ? Etc.getgrnam(group) : pw
        Process::gid = gr.gid
        Process::egid = gr.gid
        Process::uid = pw.uid
        Process::euid = pw.uid
      end 
    end   
    module_function :su

    def getservername
      host = Socket::gethostname
      begin
        Socket::gethostbyname(host)[0]
      rescue
        host
      end
    end
    module_function :getservername

    RAND_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
                 "0123456789" +
                 "abcdefghijklmnopqrstuvwxyz" 

    def random_string(len)
      rand_max = RAND_CHARS.size
      ret = "" 
      len.times{ ret << RAND_CHARS[rand(rand_max)] }
      ret 
    end
    module_function :random_string

  end
end
