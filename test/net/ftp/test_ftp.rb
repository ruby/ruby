require "net/ftp"
require "test/unit"
require "ostruct"

class FTPTest < Test::Unit::TestCase
  def test_not_connected
    ftp = Net::FTP.new
    assert_raise(Net::FTPConnectionError) do
      ftp.quit
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
    sock.peeraddr = [nil, nil, nil, "1080:0000:0000:0000:0008:0800:200c:417a"]
    ftp.instance_variable_set(:@sock, sock)
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
end
