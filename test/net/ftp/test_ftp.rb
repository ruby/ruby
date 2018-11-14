# frozen_string_literal: true

require "net/ftp"
require "test/unit"
require "ostruct"
require "stringio"
require "tempfile"
require "tmpdir"

class FTPTest < Test::Unit::TestCase
  SERVER_NAME = "localhost"
  SERVER_ADDR =
    begin
      Addrinfo.getaddrinfo(SERVER_NAME, 0, nil, :STREAM)[0].ip_address
    rescue SocketError
      "127.0.0.1"
    end
  CA_FILE = File.expand_path("../fixtures/cacert.pem", __dir__)
  SERVER_KEY = File.expand_path("../fixtures/server.key", __dir__)
  SERVER_CERT = File.expand_path("../fixtures/server.crt", __dir__)

  def setup
    @thread = nil
    @default_passive = Net::FTP.default_passive
    Net::FTP.default_passive = false
  end

  def teardown
    Net::FTP.default_passive = @default_passive
    if @thread
      @thread.join
    end
  end

  def test_not_connected
    ftp = Net::FTP.new
    assert_raise(Net::FTPConnectionError) do
      ftp.quit
    end
  end

  def test_closed_when_not_connected
    ftp = Net::FTP.new
    assert_equal(true, ftp.closed?)
    assert_nothing_raised(Net::FTPConnectionError) do
      ftp.close
    end
  end

  def test_connect_fail
    server = create_ftp_server { |sock|
      sock.print("421 Service not available, closing control connection.\r\n")
    }
    begin
      ftp = Net::FTP.new
      assert_raise(Net::FTPTempError){ ftp.connect(SERVER_ADDR, server.port) }
    ensure
      ftp.close if ftp
      server.close
    end
  end

  def test_parse227
    ftp = Net::FTP.new
    host, port = ftp.send(:parse227, "227 Entering Passive Mode (192,168,0,1,12,34)")
    assert_equal("192.168.0.1", host)
    assert_equal(3106, port)
    assert_raise(Net::FTPReplyError) do
      ftp.send(:parse227, "500 Syntax error")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse227, "227 Entering Passive Mode")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse227, "227 Entering Passive Mode (192,168,0,1,12,34,56)")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse227, "227 Entering Passive Mode (192,168,0,1)")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse227, "227 ) foo bar (")
    end
  end

  def test_parse228
    ftp = Net::FTP.new
    host, port = ftp.send(:parse228, "228 Entering Long Passive Mode (4,4,192,168,0,1,2,12,34)")
    assert_equal("192.168.0.1", host)
    assert_equal(3106, port)
    host, port = ftp.send(:parse228, "228 Entering Long Passive Mode (6,16,16,128,0,0,0,0,0,0,0,8,8,0,32,12,65,122,2,12,34)")
    assert_equal("1080:0000:0000:0000:0008:0800:200c:417a", host)
    assert_equal(3106, port)
    assert_raise(Net::FTPReplyError) do
      ftp.send(:parse228, "500 Syntax error")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse228, "228 Entering Passive Mode")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse228, "228 Entering Long Passive Mode (6,4,192,168,0,1,2,12,34)")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse228, "228 Entering Long Passive Mode (4,4,192,168,0,1,3,12,34,56)")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse228, "228 Entering Long Passive Mode (4,16,16,128,0,0,0,0,0,0,0,8,8,0,32,12,65,122,2,12,34)")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse228, "228 Entering Long Passive Mode (6,16,16,128,0,0,0,0,0,0,0,8,8,0,32,12,65,122,3,12,34,56)")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse228, "228 Entering Long Passive Mode (6,16,16,128,0,0,0,0,0,0,0,8,8,0,32,12,65,122,2,12,34,56)")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse227, "227 ) foo bar (")
    end
  end

  def test_parse229
    ftp = Net::FTP.new
    sock = OpenStruct.new
    sock.remote_address = OpenStruct.new
    sock.remote_address.ip_address = "1080:0000:0000:0000:0008:0800:200c:417a"
    ftp.instance_variable_set(:@bare_sock, sock)
    host, port = ftp.send(:parse229, "229 Entering Passive Mode (|||3106|)")
    assert_equal("1080:0000:0000:0000:0008:0800:200c:417a", host)
    assert_equal(3106, port)
    host, port = ftp.send(:parse229, "229 Entering Passive Mode (!!!3106!)")
    assert_equal("1080:0000:0000:0000:0008:0800:200c:417a", host)
    assert_equal(3106, port)
    host, port = ftp.send(:parse229, "229 Entering Passive Mode (~~~3106~)")
    assert_equal("1080:0000:0000:0000:0008:0800:200c:417a", host)
    assert_equal(3106, port)
    assert_raise(Net::FTPReplyError) do
      ftp.send(:parse229, "500 Syntax error")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse229, "229 Entering Passive Mode")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse229, "229 Entering Passive Mode (|!!3106!)")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse229, "229 Entering Passive Mode (   3106 )")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse229, "229 Entering Passive Mode (\x7f\x7f\x7f3106\x7f)")
    end
    assert_raise(Net::FTPProtoError) do
      ftp.send(:parse229, "229 ) foo bar (")
    end
  end

  def test_parse_pasv_port
    ftp = Net::FTP.new
    assert_equal(12, ftp.send(:parse_pasv_port, "12"))
    assert_equal(3106, ftp.send(:parse_pasv_port, "12,34"))
    assert_equal(795192, ftp.send(:parse_pasv_port, "12,34,56"))
    assert_equal(203569230, ftp.send(:parse_pasv_port, "12,34,56,78"))
  end

  def test_login
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_login_fail1
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("502 Command not implemented.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        assert_raise(Net::FTPPermError){ ftp.login }
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_login_fail2
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("530 Not logged in.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        assert_raise(Net::FTPPermError){ ftp.login }
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_implicit_login
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("332 Need account for login.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new(SERVER_ADDR,
                           port: server.port,
                           username: "foo",
                           password: "bar",
                           account: "baz")
        assert_equal("USER foo\r\n", commands.shift)
        assert_equal("PASS bar\r\n", commands.shift)
        assert_equal("ACCT baz\r\n", commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_s_open
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      Net::FTP.open(SERVER_ADDR, port: server.port, username: "anonymous") do
      end
      assert_equal("USER anonymous\r\n", commands.shift)
      assert_equal("PASS anonymous@\r\n", commands.shift)
      assert_equal("TYPE I\r\n", commands.shift)
      assert_equal(nil, commands.shift)
    ensure
      server.close
    end
  end

  def test_s_new_timeout_options
    ftp = Net::FTP.new
    assert_equal(nil, ftp.open_timeout)
    assert_equal(60, ftp.read_timeout)

    ftp = Net::FTP.new(nil, open_timeout: 123, read_timeout: 234)
    assert_equal(123, ftp.open_timeout)
    assert_equal(234, ftp.read_timeout)
  end

  # TODO: How can we test open_timeout?  sleep before accept cannot delay
  # connections.
  def _test_open_timeout_exceeded
    commands = []
    server = create_ftp_server(0.2) { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.open_timeout = 0.1
        ftp.connect(SERVER_ADDR, server.port)
        assert_raise(Net::OpenTimeout) do
          ftp.login
        end
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_read_timeout_exceeded
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sleep(0.1)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sleep(2.0) # Net::ReadTimeout
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sleep(0.1)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.read_timeout = 0.4
        ftp.connect(SERVER_ADDR, server.port)
        assert_raise(Net::ReadTimeout) do
          ftp.login
        end
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_read_timeout_not_exceeded
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sleep(0.1)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sleep(0.1)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sleep(0.1)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.read_timeout = 1.0
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close
        assert_equal(1.0, ftp.read_timeout)
      end
    ensure
      server.close
    end
  end

  def test_list_read_timeout_exceeded
    commands = []
    list_lines = [
      "-rw-r--r--    1 0        0               0 Mar 30 11:22 foo.txt",
      "-rw-r--r--    1 0        0               0 Mar 30 11:22 bar.txt",
      "-rw-r--r--    1 0        0               0 Mar 30 11:22 baz.txt"
    ]
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to ASCII mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("150 Here comes the directory listing.\r\n")
      begin
        conn = TCPSocket.new(host, port)
        list_lines.each_with_index do |l, i|
          if i == 1
            sleep(0.5)
          else
            sleep(0.1)
          end
          conn.print(l, "\r\n")
        end
      rescue Errno::EPIPE
      ensure
        assert_nil($!)
        conn.close
      end
      sock.print("226 Directory send OK.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.read_timeout = 0.2
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_raise(Net::ReadTimeout) do
          ftp.list
        end
        assert_equal("TYPE A\r\n", commands.shift)
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("LIST\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_list_read_timeout_not_exceeded
    commands = []
    list_lines = [
      "-rw-r--r--    1 0        0               0 Mar 30 11:22 foo.txt",
      "-rw-r--r--    1 0        0               0 Mar 30 11:22 bar.txt",
      "-rw-r--r--    1 0        0               0 Mar 30 11:22 baz.txt"
    ]
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to ASCII mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("150 Here comes the directory listing.\r\n")
      conn = TCPSocket.new(host, port)
      list_lines.each do |l|
        sleep(0.1)
        conn.print(l, "\r\n")
      end
      conn.close
      sock.print("226 Directory send OK.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.read_timeout = 1.0
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_equal(list_lines, ftp.list)
        assert_equal("TYPE A\r\n", commands.shift)
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("LIST\r\n", commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_list_fail
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to ASCII mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("553 Requested action not taken.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_raise(Net::FTPPermError){ ftp.list }
        assert_equal("TYPE A\r\n", commands.shift)
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("LIST\r\n", commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_open_data_port_fail_no_leak
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to ASCII mode.\r\n")
      line = sock.gets
      commands.push(line)
      sock.print("421 Service not available, closing control connection.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_raise(Net::FTPTempError){ ftp.list }
        assert_equal("TYPE A\r\n", commands.shift)
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_retrbinary_read_timeout_exceeded
    commands = []
    binary_data = (0..0xff).map {|i| i.chr}.join * 4 * 3
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("150 Opening BINARY mode data connection for foo (#{binary_data.size} bytes)\r\n")
      conn = TCPSocket.new(host, port)
      sleep(0.1)
      conn.print(binary_data[0,1024])
      sleep(1.0)
      conn.print(binary_data[1024, 1024]) rescue nil # may raise EPIPE or something
      conn.close
      sock.print("226 Transfer complete.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.read_timeout = 0.5
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        buf = String.new
        assert_raise(Net::ReadTimeout) do
          ftp.retrbinary("RETR foo", 1024) do |s|
            buf << s
          end
        end
        assert_equal(1024, buf.bytesize)
        assert_equal(binary_data[0, 1024], buf)
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("RETR foo\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close unless ftp.closed?
      end
    ensure
      server.close
    end
  end

  def test_retrbinary_read_timeout_not_exceeded
    commands = []
    binary_data = (0..0xff).map {|i| i.chr}.join * 4 * 3
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("150 Opening BINARY mode data connection for foo (#{binary_data.size} bytes)\r\n")
      conn = TCPSocket.new(host, port)
      binary_data.scan(/.{1,1024}/nm) do |s|
        sleep(0.2)
        conn.print(s)
      end
      conn.shutdown(Socket::SHUT_WR)
      conn.read
      conn.close
      sock.print("226 Transfer complete.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.read_timeout = 1.0
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        buf = String.new
        ftp.retrbinary("RETR foo", 1024) do |s|
          buf << s
        end
        assert_equal(binary_data.bytesize, buf.bytesize)
        assert_equal(binary_data, buf)
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("RETR foo\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_retrbinary_fail
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("550 Requested action not taken.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_raise(Net::FTPPermError){ ftp.retrbinary("RETR foo", 1024) }
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("RETR foo\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_getbinaryfile
    commands = []
    binary_data = (0..0xff).map {|i| i.chr}.join * 4 * 3
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("150 Opening BINARY mode data connection for foo (#{binary_data.size} bytes)\r\n")
      conn = TCPSocket.new(host, port)
      binary_data.scan(/.{1,1024}/nm) do |s|
        conn.print(s)
      end
      conn.shutdown(Socket::SHUT_WR)
      conn.read
      conn.close
      sock.print("226 Transfer complete.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        buf = ftp.getbinaryfile("foo", nil)
        assert_equal(binary_data, buf)
        assert_equal(Encoding::ASCII_8BIT, buf.encoding)
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("RETR foo\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_getbinaryfile_empty
    commands = []
    binary_data = ""
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("150 Opening BINARY mode data connection for foo (#{binary_data.size} bytes)\r\n")
      conn = TCPSocket.new(host, port)
      conn.shutdown(Socket::SHUT_WR)
      conn.read
      conn.close
      sock.print("226 Transfer complete.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        buf = ftp.getbinaryfile("foo", nil)
        assert_equal(binary_data, buf)
        assert_equal(Encoding::ASCII_8BIT, buf.encoding)
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("RETR foo\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_getbinaryfile_with_filename_and_block
    commands = []
    binary_data = (0..0xff).map {|i| i.chr}.join * 4 * 3
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("150 Opening BINARY mode data connection for foo (#{binary_data.size} bytes)\r\n")
      conn = TCPSocket.new(host, port)
      binary_data.scan(/.{1,1024}/nm) do |s|
        conn.print(s)
      end
      conn.shutdown(Socket::SHUT_WR)
      conn.read
      conn.close
      sock.print("226 Transfer complete.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        Tempfile.create("foo", external_encoding: "ASCII-8BIT") do |f|
          f.binmode
          buf = String.new
          res = ftp.getbinaryfile("foo", f.path) { |s|
            buf << s
          }
          assert_equal(nil, res)
          assert_equal(binary_data, buf)
          assert_equal(Encoding::ASCII_8BIT, buf.encoding)
          assert_equal(binary_data, f.read)
        end
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("RETR foo\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_storbinary
    commands = []
    binary_data = (0..0xff).map {|i| i.chr}.join * 4 * 3
    stored_data = nil
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("150 Opening BINARY mode data connection for foo\r\n")
      conn = TCPSocket.new(host, port)
      stored_data = conn.read
      conn.close
      sock.print("226 Transfer complete.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        ftp.storbinary("STOR foo", StringIO.new(binary_data), 1024)
        assert_equal(binary_data, stored_data)
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("STOR foo\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_storbinary_fail
    commands = []
    binary_data = (0..0xff).map {|i| i.chr}.join * 4 * 3
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("452 Requested file action aborted.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_raise(Net::FTPTempError){ ftp.storbinary("STOR foo", StringIO.new(binary_data), 1024) }
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("STOR foo\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_retrlines
    commands = []
    text_data = <<EOF.gsub(/\n/, "\r\n")
foo
bar
baz
EOF
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to ASCII mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("150 Opening TEXT mode data connection for foo (#{text_data.size} bytes)\r\n")
      conn = TCPSocket.new(host, port)
      text_data.each_line do |l|
        conn.print(l)
      end
      conn.shutdown(Socket::SHUT_WR)
      conn.read
      conn.close
      sock.print("226 Transfer complete.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        buf = String.new
        ftp.retrlines("RETR foo") do |line|
          buf << line + "\r\n"
        end
        assert_equal(text_data.bytesize, buf.bytesize)
        assert_equal(text_data, buf)
        assert_equal("TYPE A\r\n", commands.shift)
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("RETR foo\r\n", commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_gettextfile
    commands = []
    text_data = <<EOF.gsub(/\n/, "\r\n")
foo
bar
baz
EOF
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to ASCII mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("150 Opening TEXT mode data connection for foo (#{text_data.size} bytes)\r\n")
      conn = TCPSocket.new(host, port)
      text_data.each_line do |l|
        conn.print(l)
      end
      conn.shutdown(Socket::SHUT_WR)
      conn.read
      conn.close
      sock.print("226 Transfer complete.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        buf = ftp.gettextfile("foo", nil)
        assert_equal(text_data.gsub(/\r\n/, "\n"), buf)
        assert_equal(Encoding::ASCII_8BIT, buf.encoding)
        assert_equal("TYPE A\r\n", commands.shift)
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("RETR foo\r\n", commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_gettextfile_with_filename_and_block
    commands = []
    text_data = <<EOF.gsub(/\n/, "\r\n")
foo
bar
baz
EOF
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to ASCII mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("150 Opening TEXT mode data connection for foo (#{text_data.size} bytes)\r\n")
      conn = TCPSocket.new(host, port)
      text_data.each_line do |l|
        conn.print(l)
      end
      conn.shutdown(Socket::SHUT_WR)
      conn.read
      conn.close
      sock.print("226 Transfer complete.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        Tempfile.create("foo", external_encoding: "ascii-8bit") do |f|
          buf = String.new
          res = ftp.gettextfile("foo", f.path) { |s|
            buf << s << "\n"
          }
          assert_equal(nil, res)
          assert_equal(text_data.gsub(/\r\n/, "\n"), buf)
          assert_equal(Encoding::ASCII_8BIT, buf.encoding)
          assert_equal(buf, f.read)
        end
        assert_equal("TYPE A\r\n", commands.shift)
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("RETR foo\r\n", commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_getbinaryfile_in_list
    commands = []
    binary_data = (0..0xff).map {|i| i.chr}.join
    list_lines = [
      "-rw-r--r--    1 0        0               0 Mar 30 11:22 foo.txt",
      "-rw-r--r--    1 0        0               0 Mar 30 11:22 bar.txt",
      "-rw-r--r--    1 0        0               0 Mar 30 11:22 baz.bin"
    ]
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to ASCII mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("150 Here comes the directory listing.\r\n")
      conn = TCPSocket.new(host, port)
      list_lines.each_with_index do |l, i|
        conn.print(l, "\r\n")
      end
      conn.close
      sock.print("226 Directory send OK.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("150 Opening BINARY mode data connection for foo (#{binary_data.size} bytes)\r\n")
      conn = TCPSocket.new(host, port)
      conn.print(binary_data)
      conn.close
      sock.print("226 Transfer complete.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        ftp.list do |line|
          file = line.slice(/(\S*\.bin)\z/)
          if file
            data = ftp.getbinaryfile(file, nil)
            assert_equal(binary_data, data)
          end
        end
        assert_equal("TYPE A\r\n", commands.shift)
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("LIST\r\n", commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("RETR baz.bin\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_abort
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.gets)
      sock.print("225 No transfer to ABOR.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        ftp.abort
        assert_equal("ABOR\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_status
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.gets)
      sock.print("211 End of status\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        ftp.status
        assert_equal("STAT\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_status_path
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.gets)
      sock.print("213 End of status\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        ftp.status "/"
        assert_equal("STAT /\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_pathnames
    require 'pathname'

    commands = []
    server = create_ftp_server(0.2) { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.gets)
      sock.print("257 'foo' directory created.\r\n")
      commands.push(sock.gets)
      sock.print("250 CWD command successful.\r\n")
      commands.push(sock.gets)
      sock.print("250 CWD command successful.\r\n")
      commands.push(sock.gets)
      sock.print("250 RMD command successful.\r\n")
      commands.push(sock.gets)
      sock.print("213 test.txt  Fri, 11 Jan 2013 11:20:41 -0500.\r\n")
      commands.push(sock.gets)
      sock.print("213 test.txt  16.\r\n")
      commands.push(sock.gets)
      sock.print("350 File exists, ready for destination name\r\n")
      commands.push(sock.gets)
      sock.print("250 RNTO command successful.\r\n")
      commands.push(sock.gets)
      sock.print("250 DELE command successful.\r\n")
    }

    begin
      begin
        dir   = Pathname.new("foo")
        file  = Pathname.new("test.txt")
        file2 = Pathname.new("test2.txt")
        ftp   = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        ftp.mkdir(dir)
        ftp.chdir(dir)
        ftp.chdir("..")
        ftp.rmdir(dir)
        ftp.mdtm(file)
        ftp.size(file)
        ftp.rename(file, file2)
        ftp.delete(file)

        # TODO: These commented tests below expose the error but don't test anything:
        #   TypeError: no implicit conversion of Pathname into String
        # ftp.nlst(dir)
        # ftp.putbinaryfile(Pathname.new("/etc/hosts"), file2)
        # ftp.puttextfile(Pathname.new("/etc/hosts"), file2)
        # ftp.gettextfile(Pathname.new("/etc/hosts"), file2)
        # ftp.getbinaryfile(Pathname.new("/etc/hosts"), file2)
        # ftp.list(dir, dir, dir)

        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_match(/\ATYPE /, commands.shift)
        assert_match(/\AMKD /, commands.shift)
        assert_match(/\ACWD /, commands.shift)
        assert_match(/\ACDUP/, commands.shift)
        assert_match(/\ARMD /, commands.shift)
        assert_match(/\AMDTM /, commands.shift)
        assert_match(/\ASIZE /, commands.shift)
        assert_match(/\ARNFR /, commands.shift)
        assert_match(/\ARNTO /, commands.shift)
        assert_match(/\ADELE /, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_getmultiline
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      sock.print("123- foo\r\n")
      sock.print("bar\r\n")
      sock.print(" 123 baz\r\n")
      sock.print("123 quux\r\n")
      sock.print("123 foo\r\n")
      sock.print("foo\r\n")
      sock.print("\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        assert_equal("123- foo\nbar\n 123 baz\n123 quux\n",
                     ftp.send(:getmultiline))
        assert_equal("123 foo\n", ftp.send(:getmultiline))
        assert_equal("foo\n", ftp.send(:getmultiline))
        assert_equal("\n", ftp.send(:getmultiline))
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_size
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("213 12345\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        assert_equal(12345, ftp.size("foo.txt"))
        assert_match("SIZE foo.txt\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_mdtm
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("213 20150910161739\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        assert_equal("20150910161739", ftp.mdtm("foo.txt"))
        assert_match("MDTM foo.txt\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_mtime
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("213 20150910161739\r\n")
      commands.push(sock.gets)
      sock.print("213 20150910161739\r\n")
      commands.push(sock.gets)
      sock.print("213 20150910161739.123456\r\n")
      commands.push(sock.gets)
      sock.print("213 20150910161739.123\r\n")
      commands.push(sock.gets)
      sock.print("213 20150910161739.123456789\r\n")
      commands.push(sock.gets)
      sock.print("213 2015091016173\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        assert_equal(Time.utc(2015, 9, 10, 16, 17, 39), ftp.mtime("foo.txt"))
        assert_equal(Time.local(2015, 9, 10, 16, 17, 39),
                     ftp.mtime("foo.txt", true))
        assert_equal(Time.utc(2015, 9, 10, 16, 17, 39, 123456),
                     ftp.mtime("bar.txt"))
        assert_equal(Time.utc(2015, 9, 10, 16, 17, 39, 123000),
                     ftp.mtime("bar.txt"))
        assert_equal(Time.utc(2015, 9, 10, 16, 17, 39,
                              Rational(123456789, 1000)),
                     ftp.mtime("bar.txt"))
        assert_raise(Net::FTPProtoError) do
          ftp.mtime("quux.txt")
        end
        assert_match("MDTM foo.txt\r\n", commands.shift)
        assert_match("MDTM foo.txt\r\n", commands.shift)
        assert_match("MDTM bar.txt\r\n", commands.shift)
        assert_match("MDTM bar.txt\r\n", commands.shift)
        assert_match("MDTM bar.txt\r\n", commands.shift)
        assert_match("MDTM quux.txt\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_system
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("215 UNIX Type: L8\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        assert_equal("UNIX Type: L8", ftp.system)
        assert_match("SYST\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_mlst
    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("250- Listing foo\r\n")
      sock.print(" Type=file;Unique=FC00U1E554A;Size=1234567;Modify=20131220035929;Perm=r;Unix.mode=0644;Unix.owner=122;Unix.group=0;Unix.ctime=20131220120140;Unix.atime=20131220131139; /foo\r\n")
      sock.print("250 End\r\n")
      commands.push(sock.gets)
      sock.print("250 Malformed response\r\n")
      commands.push(sock.gets)
      sock.print("250- Listing foo\r\n")
      sock.print("\r\n")
      sock.print("250 End\r\n")
      commands.push(sock.gets)
      sock.print("250- Listing foo\r\n")
      sock.print(" abc /foo\r\n")
      sock.print("250 End\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        entry = ftp.mlst("foo")
        assert_equal("/foo", entry.pathname)
        assert_equal("file", entry.facts["type"])
        assert_equal("FC00U1E554A", entry.facts["unique"])
        assert_equal(1234567, entry.facts["size"])
        assert_equal("r", entry.facts["perm"])
        assert_equal(0644, entry.facts["unix.mode"])
        assert_equal(122, entry.facts["unix.owner"])
        assert_equal(0, entry.facts["unix.group"])
        modify = entry.facts["modify"]
        assert_equal(2013, modify.year)
        assert_equal(12, modify.month)
        assert_equal(20, modify.day)
        assert_equal(3, modify.hour)
        assert_equal(59, modify.min)
        assert_equal(29, modify.sec)
        assert_equal(true, modify.utc?)
        ctime = entry.facts["unix.ctime"]
        assert_equal(12, ctime.hour)
        assert_equal(1, ctime.min)
        assert_equal(40, ctime.sec)
        atime = entry.facts["unix.atime"]
        assert_equal(13, atime.hour)
        assert_equal(11, atime.min)
        assert_equal(39, atime.sec)
        assert_match("MLST foo\r\n", commands.shift)
        assert_raise(Net::FTPProtoError) do
          ftp.mlst("foo")
        end
        assert_match("MLST foo\r\n", commands.shift)
        assert_raise(Net::FTPProtoError) do
          ftp.mlst("foo")
        end
        assert_match("MLST foo\r\n", commands.shift)
        entry = ftp.mlst("foo")
        assert_equal("/foo", entry.pathname)
        assert_match("MLST foo\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_mlsd
    commands = []
    entry_lines = [
      "Type=file;Unique=FC00U1E554A;Size=1234567;Modify=20131220035929.123456;Perm=r; foo bar",
      "Type=cdir;Unique=FC00U1E554B;Modify=20131220035929;Perm=flcdmpe; .",
      "Type=pdir;Unique=FC00U1E554C;Modify=20131220035929;Perm=flcdmpe; ..",
    ]
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to ASCII mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("150 Here comes the directory listing.\r\n")
      begin
        conn = TCPSocket.new(host, port)
        entry_lines.each do |l|
          conn.print(l, "\r\n")
        end
      rescue Errno::EPIPE
      ensure
        assert_nil($!)
        conn.close
      end
      sock.print("226 Directory send OK.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new
        ftp.connect(SERVER_ADDR, server.port)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        entries = ftp.mlsd("/")
        assert_equal(3, entries.size)
        assert_equal("foo bar", entries[0].pathname)
        assert_equal(".", entries[1].pathname)
        assert_equal("..", entries[2].pathname)
        assert_equal("file", entries[0].facts["type"])
        assert_equal("cdir", entries[1].facts["type"])
        assert_equal("pdir", entries[2].facts["type"])
        assert_equal("flcdmpe", entries[1].facts["perm"])
        modify = entries[0].facts["modify"]
        assert_equal(2013, modify.year)
        assert_equal(12, modify.month)
        assert_equal(20, modify.day)
        assert_equal(3, modify.hour)
        assert_equal(59, modify.min)
        assert_equal(29, modify.sec)
        assert_equal(123456, modify.usec)
        assert_equal(true, modify.utc?)
        assert_equal("TYPE A\r\n", commands.shift)
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_match("MLSD /\r\n", commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_parse257
    ftp = Net::FTP.new
    assert_equal('/foo/bar',
                 ftp.send(:parse257, '257 "/foo/bar" directory created'))
    assert_equal('/foo/bar"baz',
                 ftp.send(:parse257, '257 "/foo/bar""baz" directory created'))
    assert_equal('/foo/x"y"z',
                 ftp.send(:parse257, '257 "/foo/x""y""z" directory created'))
    assert_equal('/foo/bar',
                 ftp.send(:parse257, '257 "/foo/bar" "comment"'))
    assert_equal('',
                 ftp.send(:parse257, '257 "" directory created'))
    assert_equal('',
                 ftp.send(:parse257, '257 directory created'))
    assert_raise(Net::FTPReplyError) do
      ftp.send(:parse257, "500 Syntax error")
    end
  end

  def test_putline_reject_crlf
    ftp = Net::FTP.new
    assert_raise(ArgumentError) do
      ftp.send(:putline, "\r")
    end
    assert_raise(ArgumentError) do
      ftp.send(:putline, "\n")
    end
  end

  if defined?(OpenSSL::SSL)
    def test_tls_unknown_ca
      assert_raise(OpenSSL::SSL::SSLError) do
        tls_test do |port|
          begin
            Net::FTP.new(SERVER_NAME,
                         :port => port,
                         :ssl => true)
          rescue SystemCallError
            skip $!
          end
        end
      end
    end

    def test_tls_with_ca_file
      assert_nothing_raised do
        tls_test do |port|
          begin
            Net::FTP.new(SERVER_NAME,
                         :port => port,
                         :ssl => { :ca_file => CA_FILE })
          rescue SystemCallError
            skip $!
          end
        end
      end
    end

    def test_tls_verify_none
      assert_nothing_raised do
        tls_test do |port|
          Net::FTP.new(SERVER_ADDR,
                       :port => port,
                       :ssl => { :verify_mode => OpenSSL::SSL::VERIFY_NONE })
        end
      end
    end

    def test_tls_post_connection_check
      assert_raise(OpenSSL::SSL::SSLError) do
        tls_test do |port|
          # SERVER_ADDR is different from the hostname in the certificate,
          # so the following code should raise a SSLError.
          Net::FTP.new(SERVER_ADDR,
                       :port => port,
                       :ssl => { :ca_file => CA_FILE })
        end
      end
    end

    def test_active_private_data_connection
      server = TCPServer.new(SERVER_ADDR, 0)
      port = server.addr[1]
      commands = []
      session_reused_for_data_connection = nil
      binary_data = (0..0xff).map {|i| i.chr}.join * 4 * 3
      @thread = Thread.start do
        sock = server.accept
        begin
          sock.print("220 (test_ftp).\r\n")
          commands.push(sock.gets)
          sock.print("234 AUTH success.\r\n")
          ctx = OpenSSL::SSL::SSLContext.new
          ctx.ca_file = CA_FILE
          ctx.key = File.open(SERVER_KEY) { |f|
            OpenSSL::PKey::RSA.new(f)
          }
          ctx.cert = File.open(SERVER_CERT) { |f|
            OpenSSL::X509::Certificate.new(f)
          }
          sock = OpenSSL::SSL::SSLSocket.new(sock, ctx)
          sock.sync_close = true
          begin
            sock.accept
            commands.push(sock.gets)
            sock.print("200 PSBZ success.\r\n")
            commands.push(sock.gets)
            sock.print("200 PROT success.\r\n")
            commands.push(sock.gets)
            sock.print("331 Please specify the password.\r\n")
            commands.push(sock.gets)
            sock.print("230 Login successful.\r\n")
            commands.push(sock.gets)
            sock.print("200 Switching to Binary mode.\r\n")
            line = sock.gets
            commands.push(line)
            host, port = process_port_or_eprt(sock, line)
            commands.push(sock.gets)
            sock.print("150 Opening BINARY mode data connection for foo (#{binary_data.size} bytes)\r\n")
            conn = TCPSocket.new(host, port)
            conn = OpenSSL::SSL::SSLSocket.new(conn, ctx)
            conn.sync_close = true
            conn.accept
            session_reused_for_data_connection = conn.session_reused?
            binary_data.scan(/.{1,1024}/nm) do |s|
              conn.print(s)
            end
            conn.close
            sock.print("226 Transfer complete.\r\n")
          rescue OpenSSL::SSL::SSLError
          end
        ensure
          sock.close
          server.close
        end
      end
      ftp = Net::FTP.new(SERVER_NAME,
                         port: port,
                         ssl: { ca_file: CA_FILE },
                         passive: false)
      begin
        assert_equal("AUTH TLS\r\n", commands.shift)
        assert_equal("PBSZ 0\r\n", commands.shift)
        assert_equal("PROT P\r\n", commands.shift)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        buf = ftp.getbinaryfile("foo", nil)
        assert_equal(binary_data, buf)
        assert_equal(Encoding::ASCII_8BIT, buf.encoding)
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("RETR foo\r\n", commands.shift)
        assert_equal(nil, commands.shift)
        # FIXME: The new_session_cb is known broken for clients in OpenSSL 1.1.0h.
        # See https://github.com/openssl/openssl/pull/5967 for details.
        if OpenSSL::OPENSSL_LIBRARY_VERSION !~ /OpenSSL 1.1.0h/
          assert_equal(true, session_reused_for_data_connection)
        end
      ensure
        ftp.close
      end
    end

    def test_passive_private_data_connection
      server = TCPServer.new(SERVER_ADDR, 0)
      port = server.addr[1]
      commands = []
      session_reused_for_data_connection = nil
      binary_data = (0..0xff).map {|i| i.chr}.join * 4 * 3
      @thread = Thread.start do
        sock = server.accept
        begin
          sock.print("220 (test_ftp).\r\n")
          commands.push(sock.gets)
          sock.print("234 AUTH success.\r\n")
          ctx = OpenSSL::SSL::SSLContext.new
          ctx.ca_file = CA_FILE
          ctx.key = File.open(SERVER_KEY) { |f|
            OpenSSL::PKey::RSA.new(f)
          }
          ctx.cert = File.open(SERVER_CERT) { |f|
            OpenSSL::X509::Certificate.new(f)
          }
          sock = OpenSSL::SSL::SSLSocket.new(sock, ctx)
          sock.sync_close = true
          begin
            sock.accept
            commands.push(sock.gets)
            sock.print("200 PSBZ success.\r\n")
            commands.push(sock.gets)
            sock.print("200 PROT success.\r\n")
            commands.push(sock.gets)
            sock.print("331 Please specify the password.\r\n")
            commands.push(sock.gets)
            sock.print("230 Login successful.\r\n")
            commands.push(sock.gets)
            sock.print("200 Switching to Binary mode.\r\n")
            commands.push(sock.gets)
            data_server = create_data_connection_server(sock)
            commands.push(sock.gets)
            sock.print("150 Opening BINARY mode data connection for foo (#{binary_data.size} bytes)\r\n")
            conn = data_server.accept
            conn = OpenSSL::SSL::SSLSocket.new(conn, ctx)
            conn.sync_close = true
            conn.accept
            session_reused_for_data_connection = conn.session_reused?
            binary_data.scan(/.{1,1024}/nm) do |s|
              conn.print(s)
            end
            conn.close
            data_server.close
            sock.print("226 Transfer complete.\r\n")
          rescue OpenSSL::SSL::SSLError
          end
        ensure
          sock.close
          server.close
        end
      end
      ftp = Net::FTP.new(SERVER_NAME,
                         port: port,
                         ssl: { ca_file: CA_FILE },
                         passive: true)
      begin
        assert_equal("AUTH TLS\r\n", commands.shift)
        assert_equal("PBSZ 0\r\n", commands.shift)
        assert_equal("PROT P\r\n", commands.shift)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        buf = ftp.getbinaryfile("foo", nil)
        assert_equal(binary_data, buf)
        assert_equal(Encoding::ASCII_8BIT, buf.encoding)
        assert_match(/\A(PASV|EPSV)\r\n/, commands.shift)
        assert_equal("RETR foo\r\n", commands.shift)
        assert_equal(nil, commands.shift)
        # FIXME: The new_session_cb is known broken for clients in OpenSSL 1.1.0h.
        if OpenSSL::OPENSSL_LIBRARY_VERSION !~ /OpenSSL 1.1.0h/
          assert_equal(true, session_reused_for_data_connection)
        end
      ensure
        ftp.close
      end
    end

    def test_active_clear_data_connection
      server = TCPServer.new(SERVER_ADDR, 0)
      port = server.addr[1]
      commands = []
      binary_data = (0..0xff).map {|i| i.chr}.join * 4 * 3
      @thread = Thread.start do
        sock = server.accept
        begin
          sock.print("220 (test_ftp).\r\n")
          commands.push(sock.gets)
          sock.print("234 AUTH success.\r\n")
          ctx = OpenSSL::SSL::SSLContext.new
          ctx.ca_file = CA_FILE
          ctx.key = File.open(SERVER_KEY) { |f|
            OpenSSL::PKey::RSA.new(f)
          }
          ctx.cert = File.open(SERVER_CERT) { |f|
            OpenSSL::X509::Certificate.new(f)
          }
          sock = OpenSSL::SSL::SSLSocket.new(sock, ctx)
          sock.sync_close = true
          begin
            sock.accept
            commands.push(sock.gets)
            sock.print("331 Please specify the password.\r\n")
            commands.push(sock.gets)
            sock.print("230 Login successful.\r\n")
            commands.push(sock.gets)
            sock.print("200 Switching to Binary mode.\r\n")
            line = sock.gets
            commands.push(line)
            host, port = process_port_or_eprt(sock, line)
            commands.push(sock.gets)
            sock.print("150 Opening BINARY mode data connection for foo (#{binary_data.size} bytes)\r\n")
            conn = TCPSocket.new(host, port)
            binary_data.scan(/.{1,1024}/nm) do |s|
              conn.print(s)
            end
            conn.close
            sock.print("226 Transfer complete.\r\n")
          rescue OpenSSL::SSL::SSLError
          end
        ensure
          sock.close
          server.close
        end
      end
      ftp = Net::FTP.new(SERVER_NAME,
                         port: port,
                         ssl: { ca_file: CA_FILE },
                         private_data_connection: false,
                         passive: false)
      begin
        assert_equal("AUTH TLS\r\n", commands.shift)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        buf = ftp.getbinaryfile("foo", nil)
        assert_equal(binary_data, buf)
        assert_equal(Encoding::ASCII_8BIT, buf.encoding)
        assert_match(/\A(PORT|EPRT) /, commands.shift)
        assert_equal("RETR foo\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close
      end
    end

    def test_passive_clear_data_connection
      server = TCPServer.new(SERVER_ADDR, 0)
      port = server.addr[1]
      commands = []
      binary_data = (0..0xff).map {|i| i.chr}.join * 4 * 3
      @thread = Thread.start do
        sock = server.accept
        begin
          sock.print("220 (test_ftp).\r\n")
          commands.push(sock.gets)
          sock.print("234 AUTH success.\r\n")
          ctx = OpenSSL::SSL::SSLContext.new
          ctx.ca_file = CA_FILE
          ctx.key = File.open(SERVER_KEY) { |f|
            OpenSSL::PKey::RSA.new(f)
          }
          ctx.cert = File.open(SERVER_CERT) { |f|
            OpenSSL::X509::Certificate.new(f)
          }
          sock = OpenSSL::SSL::SSLSocket.new(sock, ctx)
          sock.sync_close = true
          begin
            sock.accept
            commands.push(sock.gets)
            sock.print("331 Please specify the password.\r\n")
            commands.push(sock.gets)
            sock.print("230 Login successful.\r\n")
            commands.push(sock.gets)
            sock.print("200 Switching to Binary mode.\r\n")
            commands.push(sock.gets)
            data_server = create_data_connection_server(sock)
            commands.push(sock.gets)
            sock.print("150 Opening BINARY mode data connection for foo (#{binary_data.size} bytes)\r\n")
            conn = data_server.accept
            binary_data.scan(/.{1,1024}/nm) do |s|
              conn.print(s)
            end
            conn.close
            data_server.close
            sock.print("226 Transfer complete.\r\n")
          rescue OpenSSL::SSL::SSLError
          end
        ensure
          sock.close
          server.close
        end
      end
      ftp = Net::FTP.new(SERVER_NAME,
                         port: port,
                         ssl: { ca_file: CA_FILE },
                         private_data_connection: false,
                         passive: true)
      begin
        assert_equal("AUTH TLS\r\n", commands.shift)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        buf = ftp.getbinaryfile("foo", nil)
        assert_equal(binary_data, buf)
        assert_equal(Encoding::ASCII_8BIT, buf.encoding)
        assert_match(/\A(PASV|EPSV)\r\n/, commands.shift)
        assert_equal("RETR foo\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      ensure
        ftp.close
      end
    end

    def test_tls_connect_timeout
      server = TCPServer.new(SERVER_ADDR, 0)
      port = server.addr[1]
      commands = []
      sock = nil
      @thread = Thread.start do
        sock = server.accept
        sock.print("220 (test_ftp).\r\n")
        commands.push(sock.gets)
        sock.print("234 AUTH success.\r\n")
      end
      begin
        assert_raise(Net::OpenTimeout) do
          Net::FTP.new(SERVER_NAME,
                       port: port,
                       ssl: { ca_file: CA_FILE },
                       ssl_handshake_timeout: 0.1)
        end
        @thread.join
      ensure
        sock.close if sock
        server.close
      end
    end
  end

  def test_abort_tls
    return unless defined?(OpenSSL)

    commands = []
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("234 AUTH success.\r\n")
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.ca_file = CA_FILE
      ctx.key = File.open(SERVER_KEY) { |f|
        OpenSSL::PKey::RSA.new(f)
      }
      ctx.cert = File.open(SERVER_CERT) { |f|
        OpenSSL::X509::Certificate.new(f)
      }
      sock = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      sock.sync_close = true
      sock.accept
      commands.push(sock.gets)
      sock.print("200 PSBZ success.\r\n")
      commands.push(sock.gets)
      sock.print("200 PROT success.\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.gets)
      sock.print("225 No transfer to ABOR.\r\n")
    }
    begin
      begin
        ftp = Net::FTP.new(SERVER_NAME,
                           port: server.port,
                           ssl: { ca_file: CA_FILE })
        assert_equal("AUTH TLS\r\n", commands.shift)
        assert_equal("PBSZ 0\r\n", commands.shift)
        assert_equal("PROT P\r\n", commands.shift)
        ftp.login
        assert_match(/\AUSER /, commands.shift)
        assert_match(/\APASS /, commands.shift)
        assert_equal("TYPE I\r\n", commands.shift)
        ftp.abort
        assert_equal("ABOR\r\n", commands.shift)
        assert_equal(nil, commands.shift)
      rescue RuntimeError, LoadError
        # skip (require openssl)
      ensure
        ftp.close if ftp
      end
    ensure
      server.close
    end
  end

  def test_getbinaryfile_command_injection
    skip "| is not allowed in filename on Windows" if windows?
    [false, true].each do |resume|
      commands = []
      binary_data = (0..0xff).map {|i| i.chr}.join * 4 * 3
      server = create_ftp_server { |sock|
        sock.print("220 (test_ftp).\r\n")
        commands.push(sock.gets)
        sock.print("331 Please specify the password.\r\n")
        commands.push(sock.gets)
        sock.print("230 Login successful.\r\n")
        commands.push(sock.gets)
        sock.print("200 Switching to Binary mode.\r\n")
        line = sock.gets
        commands.push(line)
        host, port = process_port_or_eprt(sock, line)
        commands.push(sock.gets)
        sock.print("150 Opening BINARY mode data connection for |echo hello (#{binary_data.size} bytes)\r\n")
        conn = TCPSocket.new(host, port)
        binary_data.scan(/.{1,1024}/nm) do |s|
          conn.print(s)
        end
        conn.shutdown(Socket::SHUT_WR)
        conn.read
        conn.close
        sock.print("226 Transfer complete.\r\n")
      }
      begin
        chdir_to_tmpdir do
          begin
            ftp = Net::FTP.new
            ftp.resume = resume
            ftp.read_timeout = RubyVM::MJIT.enabled? ? 5 : 0.2 # use large timeout for --jit-wait
            ftp.connect(SERVER_ADDR, server.port)
            ftp.login
            assert_match(/\AUSER /, commands.shift)
            assert_match(/\APASS /, commands.shift)
            assert_equal("TYPE I\r\n", commands.shift)
            ftp.getbinaryfile("|echo hello")
            assert_equal(binary_data, File.binread("./|echo hello"))
            assert_match(/\A(PORT|EPRT) /, commands.shift)
            assert_equal("RETR |echo hello\r\n", commands.shift)
            assert_equal(nil, commands.shift)
          ensure
            ftp.close if ftp
          end
        end
      ensure
        server.close
      end
    end
  end

  def test_gettextfile_command_injection
    skip "| is not allowed in filename on Windows" if windows?
    commands = []
    text_data = <<EOF.gsub(/\n/, "\r\n")
foo
bar
baz
EOF
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to ASCII mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("150 Opening TEXT mode data connection for |echo hello (#{text_data.size} bytes)\r\n")
      conn = TCPSocket.new(host, port)
      text_data.each_line do |l|
        conn.print(l)
      end
      conn.shutdown(Socket::SHUT_WR)
      conn.read
      conn.close
      sock.print("226 Transfer complete.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      chdir_to_tmpdir do
        begin
          ftp = Net::FTP.new
          ftp.connect(SERVER_ADDR, server.port)
          ftp.login
          assert_match(/\AUSER /, commands.shift)
          assert_match(/\APASS /, commands.shift)
          assert_equal("TYPE I\r\n", commands.shift)
          ftp.gettextfile("|echo hello")
          assert_equal(text_data.gsub(/\r\n/, "\n"),
                       File.binread("./|echo hello"))
          assert_equal("TYPE A\r\n", commands.shift)
          assert_match(/\A(PORT|EPRT) /, commands.shift)
          assert_equal("RETR |echo hello\r\n", commands.shift)
          assert_equal("TYPE I\r\n", commands.shift)
          assert_equal(nil, commands.shift)
        ensure
          ftp.close if ftp
        end
      end
    ensure
      server.close
    end
  end

  def test_putbinaryfile_command_injection
    skip "| is not allowed in filename on Windows" if windows?
    commands = []
    binary_data = (0..0xff).map {|i| i.chr}.join * 4 * 3
    received_data = nil
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("150 Opening BINARY mode data connection for |echo hello (#{binary_data.size} bytes)\r\n")
      conn = TCPSocket.new(host, port)
      received_data = conn.read
      conn.close
      sock.print("226 Transfer complete.\r\n")
    }
    begin
      chdir_to_tmpdir do
        File.binwrite("./|echo hello", binary_data)
        begin
          ftp = Net::FTP.new
          ftp.read_timeout = 0.2
          ftp.connect(SERVER_ADDR, server.port)
          ftp.login
          assert_match(/\AUSER /, commands.shift)
          assert_match(/\APASS /, commands.shift)
          assert_equal("TYPE I\r\n", commands.shift)
          ftp.putbinaryfile("|echo hello")
          assert_equal(binary_data, received_data)
          assert_match(/\A(PORT|EPRT) /, commands.shift)
          assert_equal("STOR |echo hello\r\n", commands.shift)
          assert_equal(nil, commands.shift)
        ensure
          ftp.close if ftp
        end
      end
    ensure
      server.close
    end
  end

  def test_puttextfile_command_injection
    skip "| is not allowed in filename on Windows" if windows?
    commands = []
    received_data = nil
    server = create_ftp_server { |sock|
      sock.print("220 (test_ftp).\r\n")
      commands.push(sock.gets)
      sock.print("331 Please specify the password.\r\n")
      commands.push(sock.gets)
      sock.print("230 Login successful.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to ASCII mode.\r\n")
      line = sock.gets
      commands.push(line)
      host, port = process_port_or_eprt(sock, line)
      commands.push(sock.gets)
      sock.print("150 Opening TEXT mode data connection for |echo hello\r\n")
      conn = TCPSocket.new(host, port)
      received_data = conn.read
      conn.close
      sock.print("226 Transfer complete.\r\n")
      commands.push(sock.gets)
      sock.print("200 Switching to Binary mode.\r\n")
    }
    begin
      chdir_to_tmpdir do
        File.open("|echo hello", "w") do |f|
          f.puts("foo")
          f.puts("bar")
          f.puts("baz")
        end
        begin
          ftp = Net::FTP.new
          ftp.connect(SERVER_ADDR, server.port)
          ftp.login
          assert_match(/\AUSER /, commands.shift)
          assert_match(/\APASS /, commands.shift)
          assert_equal("TYPE I\r\n", commands.shift)
          ftp.puttextfile("|echo hello")
          assert_equal(<<EOF.gsub(/\n/, "\r\n"), received_data)
foo
bar
baz
EOF
          assert_equal("TYPE A\r\n", commands.shift)
          assert_match(/\A(PORT|EPRT) /, commands.shift)
          assert_equal("STOR |echo hello\r\n", commands.shift)
          assert_equal("TYPE I\r\n", commands.shift)
          assert_equal(nil, commands.shift)
        ensure
          ftp.close if ftp
        end
      end
    ensure
      server.close
    end
  end

  private

  def create_ftp_server(sleep_time = nil)
    server = TCPServer.new(SERVER_ADDR, 0)
    @thread = Thread.start do
      if sleep_time
        sleep(sleep_time)
      end
      sock = server.accept
      begin
        sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_OOBINLINE, 1)
        yield(sock)
        sock.shutdown(Socket::SHUT_WR)
        sock.read unless sock.eof?
      ensure
        sock.close
      end
    end
    def server.port
      addr[1]
    end
    return server
  end

  def tls_test
    server = TCPServer.new(SERVER_ADDR, 0)
    port = server.addr[1]
    commands = []
    @thread = Thread.start do
      sock = server.accept
      begin
        sock.print("220 (test_ftp).\r\n")
        commands.push(sock.gets)
        sock.print("234 AUTH success.\r\n")
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.ca_file = CA_FILE
        ctx.key = File.open(SERVER_KEY) { |f|
          OpenSSL::PKey::RSA.new(f)
        }
        ctx.cert = File.open(SERVER_CERT) { |f|
          OpenSSL::X509::Certificate.new(f)
        }
        sock = OpenSSL::SSL::SSLSocket.new(sock, ctx)
        sock.sync_close = true
        begin
          sock.accept
          commands.push(sock.gets)
          sock.print("200 PSBZ success.\r\n")
          commands.push(sock.gets)
          sock.print("200 PROT success.\r\n")
        rescue OpenSSL::SSL::SSLError, SystemCallError
        end
      ensure
        sock.close
        server.close
      end
    end
    ftp = yield(port)
    ftp.close

    assert_equal("AUTH TLS\r\n", commands.shift)
    assert_equal("PBSZ 0\r\n", commands.shift)
    assert_equal("PROT P\r\n", commands.shift)
  end

  def process_port_or_eprt(sock, line)
    case line
    when /\APORT (.*)/
      port_args = $1.split(/,/)
      host = port_args[0, 4].join(".")
      port = port_args[4, 2].map(&:to_i).inject {|x, y| (x << 8) + y}
      sock.print("200 PORT command successful.\r\n")
      return host, port
    when /\AEPRT \|2\|(.*?)\|(.*?)\|/
      host = $1
      port = $2.to_i
      sock.print("200 EPRT command successful.\r\n")
      return host, port
    else
      flunk "PORT or EPRT expected"
    end
  end

  def create_data_connection_server(sock)
    data_server = TCPServer.new(SERVER_ADDR, 0)
    port = data_server.local_address.ip_port
    if data_server.local_address.ipv4?
      sock.printf("227 Entering Passive Mode (127,0,0,1,%s).\r\n",
                  port.divmod(256).join(","))
    elsif data_server.local_address.ipv6?
      sock.printf("229 Entering Extended Passive Mode (|||%d|)\r\n", port)
    else
      flunk "Invalid local address"
    end
    return data_server
  end

  def chdir_to_tmpdir
    Dir.mktmpdir do |dir|
      pwd = Dir.pwd
      Dir.chdir(dir)
      begin
        yield
      ensure
        Dir.chdir(pwd)
      end
    end
  end
end
