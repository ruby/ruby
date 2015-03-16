require "test/unit"
require "net/http"
require "tempfile"
require "webrick"
require "webrick/httpauth/basicauth"
require_relative "utils"

class TestWEBrickHTTPAuth < Test::Unit::TestCase
  def test_basic_auth
    log_tester = lambda {|log, access_log|
      assert_equal(1, log.length)
      assert_match(/ERROR WEBrick::HTTPStatus::Unauthorized/, log[0])
    }
    TestWEBrick.start_httpserver({}, log_tester) {|server, addr, port, log|
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
      http.request(g){|res| assert_equal("hoge", res.body, log.call)}
      g.basic_auth("webrick", "not super")
      http.request(g){|res| assert_not_equal("hoge", res.body, log.call)}
    }
  end

  def test_basic_auth2
    log_tester = lambda {|log, access_log|
      log.reject! {|line| /\A\s*\z/ =~ line }
      pats = [
        /ERROR Basic WEBrick's realm: webrick: password unmatch\./,
        /ERROR WEBrick::HTTPStatus::Unauthorized/
      ]
      pats.each {|pat|
        assert(!log.grep(pat).empty?, "webrick log doesn't have expected error: #{pat.inspect}")
        log.reject! {|line| pat =~ line }
      }
      assert_equal([], log)
    }
    TestWEBrick.start_httpserver({}, log_tester) {|server, addr, port, log|
      realm = "WEBrick's realm"
      path = "/basic_auth2"

      Tempfile.create("test_webrick_auth") {|tmpfile|
        tmpfile.close
        tmp_pass = WEBrick::HTTPAuth::Htpasswd.new(tmpfile.path)
        tmp_pass.set_passwd(realm, "webrick", "supersecretpassword")
        tmp_pass.set_passwd(realm, "foo", "supersecretpassword")
        tmp_pass.flush

        htpasswd = WEBrick::HTTPAuth::Htpasswd.new(tmpfile.path)
        users = []
        htpasswd.each{|user, pass| users << user }
        assert_equal(2, users.size, log.call)
        assert(users.member?("webrick"), log.call)
        assert(users.member?("foo"), log.call)

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
        http.request(g){|res| assert_equal("hoge", res.body, log.call)}
        g.basic_auth("webrick", "not super")
        http.request(g){|res| assert_not_equal("hoge", res.body, log.call)}
      }
    }
  end

  def test_basic_auth3
    Tempfile.create("test_webrick_auth") {|tmpfile|
      tmpfile.puts("webrick:{SHA}GJYFRpBbdchp595jlh3Bhfmgp8k=")
      tmpfile.flush
      assert_raise(NotImplementedError){
        WEBrick::HTTPAuth::Htpasswd.new(tmpfile.path)
      }
    }

    Tempfile.create("test_webrick_auth") {|tmpfile|
      tmpfile.puts("webrick:$apr1$IOVMD/..$rmnOSPXr0.wwrLPZHBQZy0")
      tmpfile.flush
      assert_raise(NotImplementedError){
        WEBrick::HTTPAuth::Htpasswd.new(tmpfile.path)
      }
    }
  end

  DIGESTRES_ = /
    ([a-zA-Z\-]+)
      [ \t]*(?:\r\n[ \t]*)*
      =
      [ \t]*(?:\r\n[ \t]*)*
      (?:
       "((?:[^"]+|\\[\x00-\x7F])*)" |
       ([!\#$%&'*+\-.0-9A-Z^_`a-z|~]+)
      )/x

  def test_digest_auth
    log_tester = lambda {|log, access_log|
      log.reject! {|line| /\A\s*\z/ =~ line }
      pats = [
        /ERROR Digest WEBrick's realm: no credentials in the request\./,
        /ERROR WEBrick::HTTPStatus::Unauthorized/,
        /ERROR Digest WEBrick's realm: webrick: digest unmatch\./
      ]
      pats.each {|pat|
        assert(!log.grep(pat).empty?, "webrick log doesn't have expected error: #{pat.inspect}")
        log.reject! {|line| pat =~ line }
      }
      assert_equal([], log)
    }
    TestWEBrick.start_httpserver({}, log_tester) {|server, addr, port, log|
      realm = "WEBrick's realm"
      path = "/digest_auth"

      Tempfile.create("test_webrick_auth") {|tmpfile|
        tmpfile.close
        tmp_pass = WEBrick::HTTPAuth::Htdigest.new(tmpfile.path)
        tmp_pass.set_passwd(realm, "webrick", "supersecretpassword")
        tmp_pass.set_passwd(realm, "foo", "supersecretpassword")
        tmp_pass.flush

        htdigest = WEBrick::HTTPAuth::Htdigest.new(tmpfile.path)
        users = []
        htdigest.each{|user, pass| users << user }
        assert_equal(2, users.size, log.call)
        assert(users.member?("webrick"), log.call)
        assert(users.member?("foo"), log.call)

        auth = WEBrick::HTTPAuth::DigestAuth.new(
          :Realm => realm, :UserDB => htdigest,
          :Algorithm => 'MD5',
          :Logger => server.logger
        )
        server.mount_proc(path){|req, res|
          auth.authenticate(req, res)
          res.body = "hoge"
        }

        Net::HTTP.start(addr, port) do |http|
          g = Net::HTTP::Get.new(path)
          params = {}
          http.request(g) do |res|
            assert_equal('401', res.code, log.call)
            res["www-authenticate"].scan(DIGESTRES_) do |key, quoted, token|
              params[key.downcase] = token || quoted.delete('\\')
            end
             params['uri'] = "http://#{addr}:#{port}#{path}"
          end

          g['Authorization'] = credentials_for_request('webrick', "supersecretpassword", params)
          http.request(g){|res| assert_equal("hoge", res.body, log.call)}

          params['algorithm'].downcase! #4936
          g['Authorization'] = credentials_for_request('webrick', "supersecretpassword", params)
          http.request(g){|res| assert_equal("hoge", res.body, log.call)}

          g['Authorization'] = credentials_for_request('webrick', "not super", params)
          http.request(g){|res| assert_not_equal("hoge", res.body, log.call)}
        end
      }
    }
  end

  private
  def credentials_for_request(user, password, params)
    cnonce = "hoge"
    nonce_count = 1
    ha1 = "#{user}:#{params['realm']}:#{password}"
    ha2 = "GET:#{params['uri']}"
    request_digest =
      "#{Digest::MD5.hexdigest(ha1)}:" \
      "#{params['nonce']}:#{'%08x' % nonce_count}:#{cnonce}:#{params['qop']}:" \
      "#{Digest::MD5.hexdigest(ha2)}"
    "Digest username=\"#{user}\"" \
      ", realm=\"#{params['realm']}\"" \
      ", nonce=\"#{params['nonce']}\"" \
      ", uri=\"#{params['uri']}\"" \
      ", qop=#{params['qop']}" \
      ", nc=#{'%08x' % nonce_count}" \
      ", cnonce=\"#{cnonce}\"" \
      ", response=\"#{Digest::MD5.hexdigest(request_digest)}\"" \
      ", opaque=\"#{params['opaque']}\"" \
      ", algorithm=#{params['algorithm']}"
  end
end
