=begin

= net/ftp.rb

written by Shugo Maeda <shugo@ruby-lang.org>

This library is distributed under the terms of the Ruby license.
You can freely distribute/modify this library.

=end

require "socket"
require "monitor"

module Net

  class FTPError < StandardError; end
  class FTPReplyError < FTPError; end
  class FTPTempError < FTPError; end
  class FTPPermError < FTPError; end
  class FTPProtoError < FTPError; end

  class FTP
    include MonitorMixin
    
    FTP_PORT = 21
    CRLF = "\r\n"

    DEFAULT_BLOCKSIZE = 4096
    
    attr_accessor :passive, :return_code, :debug_mode, :resume
    attr_reader :welcome, :lastresp
    
    def FTP.open(host, user = nil, passwd = nil, acct = nil)
      new(host, user, passwd, acct)
    end
    
    def initialize(host = nil, user = nil, passwd = nil, acct = nil)
      super()
      @passive = false
      @return_code = "\n"
      @debug_mode = false
      @resume = false
      if host
	connect(host)
	if user
	  login(user, passwd, acct)
	end
      end
    end
    
    def open_socket(host, port)
      if defined? SOCKSsocket and ENV["SOCKS_SERVER"]
	@passive = true
	return SOCKSsocket.open(host, port)
      else
	return TCPsocket.open(host, port)
      end
    end
    private :open_socket
    
    def connect(host, port = FTP_PORT)
      if @debug_mode
	print "connect: ", host, ", ", port, "\n"
      end
      synchronize do
	@sock = open_socket(host, port)
	voidresp
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
      if line[-2, 2] == CRLF
	line = line[0 .. -3]
      elsif line[-1] == ?\r or
	  line[-1] == ?\n
	line = line[0 .. -2]
      end
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
      resp = getmultiline
      @lastresp = resp[0, 3]
      c = resp[0]
      case c
      when ?1, ?2, ?3
	return resp
      when ?4
	raise FTPTempError, resp
      when ?5
	raise FTPPermError, resp
      else
	raise FTPProtoError, resp
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
    
    def sendcmd(cmd)
      synchronize do
	putline(cmd)
	return getresp
      end
    end
    
    def voidcmd(cmd)
      synchronize do
	putline(cmd)
	voidresp
      end
    end
    
    def sendport(host, port)
      af = (@sock.peeraddr)[0]
      if af == "AF_INET"
	hbytes = host.split(".")
	pbytes = [port / 256, port % 256]
	bytes = hbytes + pbytes
	cmd = "PORT " + bytes.join(",")
      elsif af == "AF_INET6"
	cmd = "EPRT |2|" + host + "|" + sprintf("%d", port) + "|"
      else
	raise FTPProtoError, host
      end
      voidcmd(cmd)
    end
    private :sendport
    
    def makeport
      sock = TCPserver.open(@sock.addr[3], 0)
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
      thishost = Socket.gethostname
      if not thishost.index(".")
	thishost = Socket.gethostbyname(thishost)[0]
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
    
    def login(user = "anonymous", passwd = nil, acct = nil)
      if user == "anonymous" and passwd == nil
	passwd = getaddress
      end
      
      resp = ""
      synchronize do
	resp = sendcmd('USER ' + user)
	if resp[0] == ?3
	  resp = sendcmd('PASS ' + passwd)
	end
	if resp[0] == ?3
	  resp = sendcmd('ACCT ' + acct)
	end
      end
      if resp[0] != ?2
	raise FTPReplyError, resp
      end
      @welcome = resp
    end
    
    def retrbinary(cmd, blocksize, rest_offset = nil, callback = Proc.new)
      synchronize do
	voidcmd("TYPE I")
	conn = transfercmd(cmd, rest_offset)
	loop do
	  data = conn.read(blocksize)
	  break if data == nil
	  callback.call(data)
	end
	conn.close
	voidresp
      end
    end
    
    def retrlines(cmd, callback = nil)
      if block_given?
	callback = Proc.new
      elsif not callback.is_a?(Proc)
	callback = Proc.new {|line| print line, "\n"}
      end
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
	  callback.call(line)
	end
	conn.close
	voidresp
      end
    end
    
    def storbinary(cmd, file, blocksize, rest_offset = nil, callback = nil)
      if block_given?
	callback = Proc.new
      end
      use_callback = callback.is_a?(Proc)
      synchronize do
	voidcmd("TYPE I")
	conn = transfercmd(cmd, rest_offset)
	loop do
	  buf = file.read(blocksize)
	  break if buf == nil
	  conn.write(buf)
	  callback.call(buf) if use_callback
	end
	conn.close
	voidresp
      end
    end
    
    def storlines(cmd, file, callback = nil)
      if block_given?
	callback = Proc.new
      end
      use_callback = callback.is_a?(Proc)
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
	  callback.call(buf) if use_callback
	end
	conn.close
	voidresp
      end
    end
    
    def getbinaryfile(remotefile, localfile,
		      blocksize = DEFAULT_BLOCKSIZE, callback = nil)
      if block_given?
	callback = Proc.new
      end
      use_callback = callback.is_a?(Proc)
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
	  callback.call(data) if use_callback
	end
      ensure
	f.close
      end
    end
    
    def gettextfile(remotefile, localfile, callback = nil)
      if block_given?
	callback = Proc.new
      end
      use_callback = callback.is_a?(Proc)
      f = open(localfile, "w")
      begin
	retrlines("RETR " + remotefile) do |line|
	  line = line + @return_code
	  f.write(line)
	  callback.call(line) if use_callback
	end
      ensure
	f.close
      end
    end
    
    def putbinaryfile(localfile, remotefile,
		      blocksize = DEFAULT_BLOCKSIZE, callback = nil)
      if block_given?
	callback = Proc.new
      end
      use_callback = callback.is_a?(Proc)
      if @resume
	rest_offset = size(remotefile)
      else
	rest_offset = nil
      end
      f = open(localfile)
      begin
	f.binmode
	storbinary("STOR " + remotefile, f, blocksize, rest_offset) do |data|
	  callback.call(data) if use_callback
	end
      ensure
	f.close
      end
    end
    
    def puttextfile(localfile, remotefile, callback = nil)
      if block_given?
	callback = Proc.new
      end
      use_callback = callback.is_a?(Proc)
      f = open(localfile)
      begin
	storlines("STOR " + remotefile, f) do |line|
	  callback.call(line) if use_callback
	end
      ensure
	f.close
      end
    end
    
    def acct(account)
      cmd = "ACCT " + account
      voidcmd(cmd)
    end
    
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
    
    def list(*args, &block)
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
    
    def rename(fromname, toname)
      resp = sendcmd("RNFR " + fromname)
      if resp[0] != ?3
	raise FTPReplyError, resp
      end
      voidcmd("RNTO " + toname)
    end
    
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
    
    def chdir(dirname)
      if dirname == ".."
	begin
	  voidcmd("CDUP")
	  return
	rescue FTPPermError
	  if $![0, 3] != "500"
	    raise FTPPermError, $!
	  end
	end
      end
      cmd = "CWD " + dirname
      voidcmd(cmd)
    end
    
    def size(filename)
      voidcmd("TYPE I")
      resp = sendcmd("SIZE " + filename)
      if resp[0, 3] != "213" 
	raise FTPReplyError, resp
      end
      return resp[3..-1].strip.to_i
    end
    
    MDTM_REGEXP = /^(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)$/
    
    def mtime(filename, local = false)
      str = mdtm(filename)
      ary = str.scan(MDTM_REGEXP)[0].collect {|i| i.to_i}
      return local ? Time.local(*ary) : Time.gm(*ary)
    end
    
    def mkdir(dirname)
      resp = sendcmd("MKD " + dirname)
      return parse257(resp)
    end
    
    def rmdir(dirname)
      voidcmd("RMD " + dirname)
    end
    
    def pwd
      resp = sendcmd("PWD")
      return parse257(resp)
    end
    alias getdir pwd
    
    def system
      resp = sendcmd("SYST")
      if resp[0, 3] != "215"
	raise FTPReplyError, resp
      end
      return resp[4 .. -1]
    end
    
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
    
    def status
      line = "STAT" + CRLF
      print "put: STAT\n" if @debug_mode
      @sock.send(line, Socket::MSG_OOB)
      return getresp
    end
    
    def mdtm(filename)
      resp = sendcmd("MDTM " + filename)
      if resp[0, 3] == "213"
	return resp[3 .. -1].strip
      end
    end
    
    def help(arg = nil)
      cmd = "HELP"
      if arg
	cmd = cmd + " " + arg
      end
      sendcmd(cmd)
    end
    
    def quit
      voidcmd("QUIT")
    end
    
    def close
      @sock.close if @sock and not @sock.closed?
    end
    
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
