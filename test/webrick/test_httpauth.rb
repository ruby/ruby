require "test/unit"
require "net/http"
require "tempfile"
require "webrick"
require "webrick/httpauth/basicauth"
require File.join(File.dirname(__FILE__), "utils.rb")

class TestWEBrickHTTPAuth < Test::Unit::TestCase
  def test_basic_auth
    TestWEBrick.start_httpserver{|server, addr, port|
      realm = "WEBrick's realm"
      path = "/basic_auth"

      server.mount_proc(path){|req, res|
        WEBrick::HTTPAuth.basic_auth(req, res, realm){|user, pass|
          user == "webrick" && pass == "supersecretpassword"
        }
        res.body = "hoge"
      }
      http = Net::HTTP.new(addr, port)
      g = Net::HTTP::Get.new(path)
      g.basic_auth("webrick", "supersecretpassword")
      http.request(g){|res| assert_equal("hoge", res.body)}
      g.basic_auth("webrick", "not super")
      http.request(g){|res| assert_not_equal("hoge", res.body)}
    }
  end

  def test_basic_auth2
    TestWEBrick.start_httpserver{|server, addr, port|
      realm = "WEBrick's realm"
      path = "/basic_auth2"

      tmpfile = Tempfile.new("test_webrick_auth")
      tmpfile.close
      tmp_pass = WEBrick::HTTPAuth::Htpasswd.new(tmpfile.path)
      tmp_pass.set_passwd(realm, "webrick", "supersecretpassword")
      tmp_pass.set_passwd(realm, "foo", "supersecretpassword")
      tmp_pass.flush

      htpasswd = WEBrick::HTTPAuth::Htpasswd.new(tmpfile.path)
      users = []
      htpasswd.each{|user, pass| users << user }
      assert_equal(2, users.size)
      assert(users.member?("webrick"))
      assert(users.member?("foo"))

      server.mount_proc(path){|req, res|
        auth = WEBrick::HTTPAuth::BasicAuth.new(
          :Realm => realm, :UserDB => htpasswd,
          :Logger => server.logger
        )
        auth.authenticate(req, res)
        res.body = "hoge"
      }
      http = Net::HTTP.new(addr, port)
      g = Net::HTTP::Get.new(path)
      g.basic_auth("webrick", "supersecretpassword")
      http.request(g){|res| assert_equal("hoge", res.body)}
      g.basic_auth("webrick", "not super")
      http.request(g){|res| assert_not_equal("hoge", res.body)}
    }
  end

  def test_basic_auth3
    tmpfile = Tempfile.new("test_webrick_auth")
    tmpfile.puts("webrick:{SHA}GJYFRpBbdchp595jlh3Bhfmgp8k=")
    tmpfile.flush
    assert_raises(NotImplementedError){
      WEBrick::HTTPAuth::Htpasswd.new(tmpfile.path)
    }
    tmpfile.close(true)

    tmpfile = Tempfile.new("test_webrick_auth")
    tmpfile.puts("webrick:$apr1$IOVMD/..$rmnOSPXr0.wwrLPZHBQZy0")
    tmpfile.flush
    assert_raises(NotImplementedError){
      WEBrick::HTTPAuth::Htpasswd.new(tmpfile.path)
    }
    tmpfile.close(true)
  end
end
