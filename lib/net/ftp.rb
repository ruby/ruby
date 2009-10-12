# 
# = net/ftp.rb - FTP Client Library
# 
# Written by Shugo Maeda <shugo@ruby-lang.org>.
#
# Documentation by Gavin Sinclair, sourced from "Programming Ruby" (Hunt/Thomas)
# and "Ruby In a Nutshell" (Matsumoto), used with permission.
# 
# This library is distributed under the terms of the Ruby license.
# You can freely distribute/modify this library.
#
# It is included in the Ruby standard library.
#
# See the Net::FTP class for an overview.
#

require "socket"
require "monitor"

module Net

  # :stopdoc:
  class FTPError < StandardError; end
  class FTPReplyError < FTPError; end
  class FTPTempError < FTPError; end 
  class FTPPermError < FTPError; end 
  class FTPProtoError < FTPError; end
  # :startdoc:

  #
  # This class implements the File Transfer Protocol.  If you have used a
  # command-line FTP program, and are familiar with the commands, you will be
  # able to use this class easily.  Some extra features are included to take
  # advantage of Ruby's style and strengths.
  #
  # == Example
  # 
  #   require 'net/ftp'
  #
  # === Example 1
  #  
  #   ftp = Net::FTP.new('ftp.netlab.co.jp')
  #   ftp.login
  #   files = ftp.chdir('pub/lang/ruby/contrib')
  #   files = ftp.list('n*')
  #   ftp.getbinaryfile('nif.rb-0.91.gz', 'nif.gz', 1024)
  #   ftp.close
  #
  # === Example 2
  #
  #   Net::FTP.open('ftp.netlab.co.jp') do |ftp|
  #     ftp.login
  #     files = ftp.chdir('pub/lang/ruby/contrib')
  #     files = ftp.list('n*')
  #     ftp.getbinaryfile('nif.rb-0.91.gz', 'nif.gz', 1024)
  #   end
  #
  # == Major Methods
  #
  # The following are the methods most likely to be useful to users:
  # - FTP.open
  # - #getbinaryfile
  # - #gettextfile
  # - #putbinaryfile
  # - #puttextfile
  # - #chdir
  # - #nlst
  # - #size
  # - #rename
  # - #delete
  #
  class FTP
    include MonitorMixin
    
    # :stopdoc:
    FTP_PORT = 21
    CRLF = "\r\n"
    DEFAULT_BLOCKSIZE = 4096
    # :startdoc:
    
    # When +true+, transfers are performed in binary mode.  Default: +true+.
    attr_accessor :binary

    # When +true+, the connection is in passive mode.  Default: +false+.
    attr_accessor :passive

    # When +true+, all traffic to and from the server is written
    # to +$stdout+.  Default: +false+.
    attr_accessor :debug_mode

    # Sets or retrieves the +resume+ status, which decides whether incomplete
    # transfers are resumed or restarted.  Default: +false+.
    attr_accessor :resume

    # The server's welcome message.
    attr_reader :welcome

    # The server's last response code.
    attr_reader :last_response_code
    alias lastresp last_response_code

    # The server's last response.
    attr_reader :last_response
    
    #
    # A synonym for <tt>FTP.new</tt>, but with a mandatory host parameter.
    #
    # If a block is given, it is passed the +FTP+ object, which will be closed
    # when the block finishes, or when an exception is raised.
    #
    def FTP.open(host, user = nil, passwd = nil, acct = nil)
      if block_given?
        ftp = new(host, user, passwd, acct)
        begin
          yield ftp
        ensure
          ftp.close
        end
      else
        new(host, user, passwd, acct)
      end
    end
    
    #
    # Creates and returns a new +FTP+ object. If a +host+ is given, a connection
    # is made. Additionally, if the +user+ is given, the given user name,
    # password, and (optionally) account are used to log in.  See #login.
    #
    def initialize(host = nil, user = nil, passwd = nil, acct = nil)
      super()
      @binary = true
      @passive = false
      @debug_mode = false
      @resume = false
      if host
	connect(host)
	if user
	  login(user, passwd, acct)
	end
      end
    end

    # Obsolete
    def return_code
      $stderr.puts("warning: Net::FTP#return_code is obsolete and do nothing")
      return "\n"
    end

    # Obsolete
    def return_code=(s)
      $stderr.puts("warning: Net::FTP#return_code= is obsolete and do nothing")
    end

    def open_socket(host, port)
      if defined? SOCKSSocket and ENV["SOCKS_SERVER"]
	@passive = true
	return SOCKSSocket.open(host, port)
      else
	return TCPSocket.open(host, port)
      end
    end
    private :open_socket
    
    #
    # Establishes an FTP connection to host, optionally overriding the default
    # port. If the environment variable +SOCKS_SERVER+ is set, sets up the
    # connection through a SOCKS proxy. Raises an exception (typically
    # <tt>Errno::ECONNREFUSED</tt>) if the connection cannot be established.
    #
    def connect(host, port = FTP_PORT)
      if @debug_mode
	print "connect: ", host, ", ", port, "\n"
      end
      synchronize do
	@sock = open_socket(host, port)
	voidresp
      end
    end

    #
    # WRITEME or make private
    #
    def set_socket(sock, get_greeting = true)
      synchronize do
	@sock = sock
	if get_greeting
	  voidresp
	end
      end
    end

    def sanitize(s)
      if s =~ /^PASS /i
	return s[0, 5] + "*" * (s.length - 5)
      else
	return s
      end
    end
    private :sanitize
    
    def putline(line)
      if @debug_mode
	print "put: ", sanitize(line), "\n"
      end
      line = line + CRLF
      @sock.write(line)
    end
    private :putline
    
    def getline
      line = @sock.readline # if get EOF, raise EOFError
      line.sub!(/(\r\n|\n|\r)\z/n, "")
      if @debug_mode
	print "get: ", sanitize(line), "\n"
      end
      return line
    end
    private :getline
    
    def getmultiline
      line = getline
      buff = line
      if line[3] == ?-
	  code = line[0, 3]
	begin
	  line = getline
	  buff << "\n" << line
	end until line[0, 3] == code and line[3] != ?-
      end
      return buff << "\n"
    end
    private :getmultiline
    
    def getresp
      @last_response = getmultiline
      @last_response_code = @last_response[0, 3]
      case @last_response_code
      when /\A[123]/
	return @last_response
      when /\A4/
	raise FTPTempError, @last_response
      when /\A5/
	raise FTPPermError, @last_response
      else
	raise FTPProtoError, @last_response
      end
    end
    private :getresp
    
    def voidresp
      resp = getresp
      if resp[0] != ?2
	raise FTPReplyError, resp
      end
    end
    private :voidresp
    
    #
    # Sends a command and returns the response.
    #
    def sendcmd(cmd)
      synchronize do
	putline(cmd)
	return getresp
      end
    end
    
    #
    # Sends a command and expect a response beginning with '2'.
    #
    def voidcmd(cmd)
      synchronize do
	putline(cmd)
	voidresp
      end
    end
    
    def sendport(host, port)
      af = (@sock.peeraddr)[0]
      if af == "AF_INET"
	cmd = "PORT " + (host.split(".") + port.divmod(256)).join(",")
      elsif af == "AF_INET6"
	cmd = sprintf("EPRT |2|%s|%d|", host, port)
      else
	raise FTPProtoError, host
      end
      voidcmd(cmd)
    end
    private :sendport
    
    def makeport
      sock = TCPServer.open(@sock.addr[3], 0)
      port = sock.addr[1]
      host = sock.addr[3]
      resp = sendport(host, port)
      return sock
    end
    private :makeport
    
    def makepasv
      if @sock.peeraddr[0] == "AF_INET"
	host, port = parse227(sendcmd("PASV"))
      else
	host, port = parse229(sendcmd("EPSV"))
	#     host, port = parse228(sendcmd("LPSV"))
      end
      return host, port
    end
    private :makepasv
    
    def transfercmd(cmd, rest_offset = nil)
      if @passive
	host, port = makepasv
	conn = open_socket(host, port)
	if @resume and rest_offset
	  resp = sendcmd("REST " + rest_offset.to_s) 
	  if resp[0] != ?3
	    raise FTPReplyError, resp
	  end
	end
	resp = sendcmd(cmd)
        # skip 2XX for some ftp servers
        resp = getresp if resp[0] == ?2
	if resp[0] != ?1
	  raise FTPReplyError, resp
	end
      else
	sock = makeport
	if @resume and rest_offset
	  resp = sendcmd("REST " + rest_offset.to_s) 
	  if resp[0] != ?3
	    raise FTPReplyError, resp
	  end
	end
	resp = sendcmd(cmd)
        # skip 2XX for some ftp servers
        resp = getresp if resp[0] == ?2
	if resp[0] != ?1
	  raise FTPReplyError, resp
	end
	conn = sock.accept
	sock.close
      end
      return conn
    end
    private :transfercmd
    
    def getaddress
      thishost = Socket.gethostname rescue ""
      if not thishost.index(".")
        thishost = Socket.gethostbyname(thishost)[0] rescue ""
      end
      if ENV.has_key?("LOGNAME")
	realuser = ENV["LOGNAME"]
      elsif ENV.has_key?("USER")
	realuser = ENV["USER"]
      else
	realuser = "anonymous"
      end
      return realuser + "@" + thishost
    end
    private :getaddress
    
    #
    # Logs in to the remote host. The session must have been previously
    # connected.  If +user+ is the string "anonymous" and the +password+ is
    # +nil+, a password of <tt>user@host</tt> is synthesized. If the +acct+
    # parameter is not +nil+, an FTP ACCT command is sent following the
    # successful login.  Raises an exception on error (typically
    # <tt>Net::FTPPermError</tt>).
    #
    def login(user = "anonymous", passwd = nil, acct = nil)
      if user == "anonymous" and passwd == nil
	passwd = getaddress
      end
      
      resp = ""
      synchronize do
	resp = sendcmd('USER ' + user)
	if resp[0] == ?3
          raise FTPReplyError, resp if passwd.nil?
	  resp = sendcmd('PASS ' + passwd)
	end
	if resp[0] == ?3
          raise FTPReplyError, resp if acct.nil?
	  resp = sendcmd('ACCT ' + acct)
	end
      end
      if resp[0] != ?2
	raise FTPReplyError, resp
      end
      @welcome = resp
    end
    
    #
    # Puts the connection into binary (image) mode, issues the given command,
    # and fetches the data returned, passing it to the associated block in
    # chunks of +blocksize+ characters. Note that +cmd+ is a server command
    # (such as "RETR myfile").
    #
    def retrbinary(cmd, blocksize, rest_offset = nil) # :yield: data
      synchronize do
	voidcmd("TYPE I")
	conn = transfercmd(cmd, rest_offset)
	loop do
	  data = conn.read(blocksize)
	  break if data == nil
	  yield(data)
	end
	conn.close
	voidresp
      end
    end
    
    #
    # Puts the connection into ASCII (text) mode, issues the given command, and
    # passes the resulting data, one line at a time, to the associated block. If
    # no block is given, prints the lines. Note that +cmd+ is a server command
    # (such as "RETR myfile").
    #
    def retrlines(cmd) # :yield: line
      synchronize do
	voidcmd("TYPE A")
	conn = transfercmd(cmd)
	loop do
	  line = conn.gets
	  break if line == nil
	  if line[-2, 2] == CRLF
	    line = line[0 .. -3]
	  elsif line[-1] == ?\n
	    line = line[0 .. -2]
	  end
	  yield(line)
	end
	conn.close
	voidresp
      end
    end
    
    #
    # Puts the connection into binary (image) mode, issues the given server-side
    # command (such as "STOR myfile"), and sends the contents of the file named
    # +file+ to the server. If the optional block is given, it also passes it
    # the data, in chunks of +blocksize+ characters.
    #
    def storbinary(cmd, file, blocksize, rest_offset = nil, &block) # :yield: data
      if rest_offset
        file.seek(rest_offset, IO::SEEK_SET)
      end
      synchronize do
	voidcmd("TYPE I")
	conn = transfercmd(cmd, rest_offset)
	loop do
	  buf = file.read(blocksize)
	  break if buf == nil
	  conn.write(buf)
	  yield(buf) if block
	end
	conn.close
	voidresp
      end
    end
    
    #
    # Puts the connection into ASCII (text) mode, issues the given server-side
    # command (such as "STOR myfile"), and sends the contents of the file
    # named +file+ to the server, one line at a time. If the optional block is
    # given, it also passes it the lines.
    #
    def storlines(cmd, file, &block) # :yield: line
      synchronize do
	voidcmd("TYPE A")
	conn = transfercmd(cmd)
	loop do
	  buf = file.gets
	  break if buf == nil
	  if buf[-2, 2] != CRLF
	    buf = buf.chomp + CRLF
	  end
	  conn.write(buf)
	  yield(buf) if block
	end
	conn.close
	voidresp
      end
    end

    #
    # Retrieves +remotefile+ in binary mode, storing the result in +localfile+.
    # If a block is supplied, it is passed the retrieved data in +blocksize+
    # chunks.
    #
    def getbinaryfile(remotefile, localfile = File.basename(remotefile),
		      blocksize = DEFAULT_BLOCKSIZE, &block) # :yield: data
      if @resume
	rest_offset = File.size?(localfile)
	f = open(localfile, "a")
      else
	rest_offset = nil
	f = open(localfile, "w")
      end
      begin
	f.binmode
	retrbinary("RETR " + remotefile, blocksize, rest_offset) do |data|
	  f.write(data)
	  yield(data) if block
	end
      ensure
	f.close
      end
    end
    
    #
    # Retrieves +remotefile+ in ASCII (text) mode, storing the result in
    # +localfile+. If a block is supplied, it is passed the retrieved data one
    # line at a time.
    #
    def gettextfile(remotefile, localfile = File.basename(remotefile), &block) # :yield: line
      f = open(localfile, "w")
      begin
	retrlines("RETR " + remotefile) do |line|
	  f.puts(line)
	  yield(line) if block
	end
      ensure
	f.close
      end
    end

    #
    # Retrieves +remotefile+ in whatever mode the session is set (text or
    # binary).  See #gettextfile and #getbinaryfile.
    #
    def get(remotefile, localfile = File.basename(remotefile),
	    blocksize = DEFAULT_BLOCKSIZE, &block) # :yield: data
      unless @binary
	gettextfile(remotefile, localfile, &block)
      else
	getbinaryfile(remotefile, localfile, blocksize, &block)
      end
    end
    
    #
    # Transfers +localfile+ to the server in binary mode, storing the result in
    # +remotefile+. If a block is supplied, calls it, passing in the transmitted
    # data in +blocksize+ chunks.
    #
    def putbinaryfile(localfile, remotefile = File.basename(localfile),
		      blocksize = DEFAULT_BLOCKSIZE, &block) # :yield: data
      if @resume
        begin
          rest_offset = size(remotefile)
        rescue Net::FTPPermError
          rest_offset = nil
        end
      else
	rest_offset = nil
      end
      f = open(localfile)
      begin
	f.binmode
	storbinary("STOR " + remotefile, f, blocksize, rest_offset, &block)
      ensure
	f.close
      end
    end
    
    #
    # Transfers +localfile+ to the server in ASCII (text) mode, storing the result
    # in +remotefile+. If callback or an associated block is supplied, calls it,
    # passing in the transmitted data one line at a time.
    #
    def puttextfile(localfile, remotefile = File.basename(localfile), &block) # :yield: line
      f = open(localfile)
      begin
	storlines("STOR " + remotefile, f, &block)
      ensure
	f.close
      end
    end

    #
    # Transfers +localfile+ to the server in whatever mode the session is set
    # (text or binary).  See #puttextfile and #putbinaryfile.
    #
    def put(localfile, remotefile = File.basename(localfile),
	    blocksize = DEFAULT_BLOCKSIZE, &block)
      unless @binary
	puttextfile(localfile, remotefile, &block)
      else
	putbinaryfile(localfile, remotefile, blocksize, &block)
      end
    end

    #
    # Sends the ACCT command.  TODO: more info.
    #
    def acct(account)
      cmd = "ACCT " + account
      voidcmd(cmd)
    end
    
    #
    # Returns an array of filenames in the remote directory.
    #
    def nlst(dir = nil)
      cmd = "NLST"
      if dir
	cmd = cmd + " " + dir
      end
      files = []
      retrlines(cmd) do |line|
	files.push(line)
      end
      return files
    end
    
    #
    # Returns an array of file information in the directory (the output is like
    # `ls -l`).  If a block is given, it iterates through the listing.
    #
    def list(*args, &block) # :yield: line
      cmd = "LIST"
      args.each do |arg|
	cmd = cmd + " " + arg
      end
      if block
	retrlines(cmd, &block)
      else
	lines = []
	retrlines(cmd) do |line|
	  lines << line
	end
	return lines
      end
    end
    alias ls list
    alias dir list
    
    #
    # Renames a file on the server.
    #
    def rename(fromname, toname)
      resp = sendcmd("RNFR " + fromname)
      if resp[0] != ?3
	raise FTPReplyError, resp
      end
      voidcmd("RNTO " + toname)
    end
    
    #
    # Deletes a file on the server.
    #
    def delete(filename)
      resp = sendcmd("DELE " + filename)
      if resp[0, 3] == "250"
	return
      elsif resp[0] == ?5
	raise FTPPermError, resp
      else
	raise FTPReplyError, resp
      end
    end
    
    #
    # Changes the (remote) directory.
    #
    def chdir(dirname)
      if dirname == ".."
	begin
	  voidcmd("CDUP")
	  return
	rescue FTPPermError => e
	  if e.message[0, 3] != "500"
	    raise e
	  end
	end
      end
      cmd = "CWD " + dirname
      voidcmd(cmd)
    end
    
    #
    # Returns the size of the given (remote) filename.
    #
    def size(filename)
      voidcmd("TYPE I")
      resp = sendcmd("SIZE " + filename)
      if resp[0, 3] != "213" 
	raise FTPReplyError, resp
      end
      return resp[3..-1].strip.to_i
    end
    
    MDTM_REGEXP = /^(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/  # :nodoc:
    
    #
    # Returns the last modification time of the (remote) file.  If +local+ is
    # +true+, it is returned as a local time, otherwise it's a UTC time.
    #
    def mtime(filename, local = false)
      str = mdtm(filename)
      ary = str.scan(MDTM_REGEXP)[0].collect {|i| i.to_i}
      return local ? Time.local(*ary) : Time.gm(*ary)
    end
    
    #
    # Creates a remote directory.
    #
    def mkdir(dirname)
      resp = sendcmd("MKD " + dirname)
      return parse257(resp)
    end
    
    #
    # Removes a remote directory.
    #
    def rmdir(dirname)
      voidcmd("RMD " + dirname)
    end
    
    #
    # Returns the current remote directory.
    #
    def pwd
      resp = sendcmd("PWD")
      return parse257(resp)
    end
    alias getdir pwd
    
    #
    # Returns system information.
    #
    def system
      resp = sendcmd("SYST")
      if resp[0, 3] != "215"
	raise FTPReplyError, resp
      end
      return resp[4 .. -1]
    end
    
    #
    # Aborts the previous command (ABOR command).
    #
    def abort
      line = "ABOR" + CRLF
      print "put: ABOR\n" if @debug_mode
      @sock.send(line, Socket::MSG_OOB)
      resp = getmultiline
      unless ["426", "226", "225"].include?(resp[0, 3])
	raise FTPProtoError, resp
      end
      return resp
    end
    
    #
    # Returns the status (STAT command).
    #
    def status
      line = "STAT" + CRLF
      print "put: STAT\n" if @debug_mode
      @sock.send(line, Socket::MSG_OOB)
      return getresp
    end
    
    #
    # Issues the MDTM command.  TODO: more info.
    #
    def mdtm(filename)
      resp = sendcmd("MDTM " + filename)
      if resp[0, 3] == "213"
	return resp[3 .. -1].strip
      end
    end
    
    #
    # Issues the HELP command.
    #
    def help(arg = nil)
      cmd = "HELP"
      if arg
	cmd = cmd + " " + arg
      end
      sendcmd(cmd)
    end
    
    #
    # Exits the FTP session.
    #
    def quit
      voidcmd("QUIT")
    end

    #
    # Issues a NOOP command.
    #
    def noop
      voidcmd("NOOP")
    end

    #
    # Issues a SITE command.
    #
    def site(arg)
      cmd = "SITE " + arg
      voidcmd(cmd)
    end
    
    #
    # Closes the connection.  Further operations are impossible until you open
    # a new connection with #connect.
    #
    def close
      @sock.close if @sock and not @sock.closed?
    end
    
    #
    # Returns +true+ iff the connection is closed.
    #
    def closed?
      @sock == nil or @sock.closed?
    end
    
    def parse227(resp)
      if resp[0, 3] != "227"
	raise FTPReplyError, resp
      end
      left = resp.index("(")
      right = resp.index(")")
      if left == nil or right == nil
	raise FTPProtoError, resp
      end
      numbers = resp[left + 1 .. right - 1].split(",")
      if numbers.length != 6
	raise FTPProtoError, resp
      end
      host = numbers[0, 4].join(".")
      port = (numbers[4].to_i << 8) + numbers[5].to_i
      return host, port
    end
    private :parse227
    
    def parse228(resp)
      if resp[0, 3] != "228"
	raise FTPReplyError, resp
      end
      left = resp.index("(")
      right = resp.index(")")
      if left == nil or right == nil
	raise FTPProtoError, resp
      end
      numbers = resp[left + 1 .. right - 1].split(",")
      if numbers[0] == "4"
	if numbers.length != 9 || numbers[1] != "4" || numbers[2 + 4] != "2"
	  raise FTPProtoError, resp
	end
	host = numbers[2, 4].join(".")
	port = (numbers[7].to_i << 8) + numbers[8].to_i
      elsif numbers[0] == "6"
	if numbers.length != 21 || numbers[1] != "16" || numbers[2 + 16] != "2"
	  raise FTPProtoError, resp
	end
	v6 = ["", "", "", "", "", "", "", ""]
	for i in 0 .. 7
	  v6[i] = sprintf("%02x%02x", numbers[(i * 2) + 2].to_i,
			  numbers[(i * 2) + 3].to_i)
	end
	host = v6[0, 8].join(":")
	port = (numbers[19].to_i << 8) + numbers[20].to_i
      end 
      return host, port
    end
    private :parse228
    
    def parse229(resp)
      if resp[0, 3] != "229"
	raise FTPReplyError, resp
      end
      left = resp.index("(")
      right = resp.index(")")
      if left == nil or right == nil
	raise FTPProtoError, resp
      end
      numbers = resp[left + 1 .. right - 1].split(resp[left + 1, 1])
      if numbers.length != 4
	raise FTPProtoError, resp
      end
      port = numbers[3].to_i
      host = (@sock.peeraddr())[3]
      return host, port
    end
    private :parse229
    
    def parse257(resp)
      if resp[0, 3] != "257"
	raise FTPReplyError, resp
      end
      if resp[3, 2] != ' "'
	return ""
      end
      dirname = ""
      i = 5
      n = resp.length
      while i < n
	c = resp[i, 1]
	i = i + 1
	if c == '"'
	  if i > n or resp[i, 1] != '"'
	    break
	  end
	  i = i + 1
	end
	dirname = dirname + c
      end
      return dirname
    end
    private :parse257
  end

end


# Documentation comments:
#  - sourced from pickaxe and nutshell, with improvements (hopefully)
#  - three methods should be private (search WRITEME)
#  - two methods need more information (search TODO)
