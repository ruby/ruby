require "webrick"
require File.join(File.dirname(__FILE__), "utils.rb")
require "test/unit"
begin
  loadpath = $:.dup
  $:.replace($: | [File.expand_path("../ruby", File.dirname(__FILE__))])
  require 'envutil'
ensure
  $:.replace(loadpath)
end

class TestWEBrickCGI < Test::Unit::TestCase
  def test_cgi
    accepted = started = stopped = 0
    requested0 = requested1 = 0
    config = {
      :CGIInterpreter => EnvUtil.rubybin,
      :DocumentRoot => File.dirname(__FILE__),
      :DirectoryIndex => ["webrick.cgi"],
    }
    if RUBY_PLATFORM =~ /mswin32|mingw|cygwin|bccwin32/
      config[:CGIPathEnv] = ENV['PATH'] # runtime dll may not be in system dir.
    end
    TestWEBrick.start_httpserver(config){|server, addr, port|
      http = Net::HTTP.new(addr, port)
      req = Net::HTTP::Get.new("/webrick.cgi")
      http.request(req){|res| assert_equal("/webrick.cgi", res.body)}
      req = Net::HTTP::Get.new("/webrick.cgi/path/info")
      http.request(req){|res| assert_equal("/path/info", res.body)}
      req = Net::HTTP::Get.new("/webrick.cgi/%3F%3F%3F?foo=bar")
      http.request(req){|res| assert_equal("/???", res.body)}
      req = Net::HTTP::Get.new("/webrick.cgi/%A4%DB%A4%B2/%A4%DB%A4%B2")
      http.request(req){|res|
        assert_equal("/\xA4\xDB\xA4\xB2/\xA4\xDB\xA4\xB2", res.body)}
      req = Net::HTTP::Get.new("/webrick.cgi?a=1;a=2;b=x")
      http.request(req){|res| assert_equal("a=1, a=2, b=x", res.body)}
      req = Net::HTTP::Get.new("/webrick.cgi?a=1&a=2&b=x")
      http.request(req){|res| assert_equal("a=1, a=2, b=x", res.body)}

      req = Net::HTTP::Post.new("/webrick.cgi?a=x;a=y;b=1")
      req["Content-Type"] = "application/x-www-form-urlencoded"
      http.request(req, "a=1;a=2;b=x"){|res|
        assert_equal("a=1, a=2, b=x", res.body)}
      req = Net::HTTP::Post.new("/webrick.cgi?a=x&a=y&b=1")
      req["Content-Type"] = "application/x-www-form-urlencoded"
      http.request(req, "a=1&a=2&b=x"){|res|
        assert_equal("a=1, a=2, b=x", res.body)}
      req = Net::HTTP::Get.new("/")
      http.request(req){|res|
        ary = res.body.to_a
        assert_match(%r{/$}, ary[0])
        assert_match(%r{/webrick.cgi$}, ary[1])
      }

      req = Net::HTTP::Get.new("/webrick.cgi")
      req["Cookie"] = "CUSTOMER=WILE_E_COYOTE; PART_NUMBER=ROCKET_LAUNCHER_0001"
      http.request(req){|res|
        assert_equal(
          "CUSTOMER=WILE_E_COYOTE\nPART_NUMBER=ROCKET_LAUNCHER_0001\n",
          res.body)
      }

      req = Net::HTTP::Get.new("/webrick.cgi")
      cookie =  %{$Version="1"; }
      cookie << %{Customer="WILE_E_COYOTE"; $Path="/acme"; }
      cookie << %{Part_Number="Rocket_Launcher_0001"; $Path="/acme"; }
      cookie << %{Shipping="FedEx"; $Path="/acme"}
      req["Cookie"] = cookie
      http.request(req){|res|
        assert_equal("Customer=WILE_E_COYOTE, Shipping=FedEx",
                     res["Set-Cookie"])
        assert_equal("Customer=WILE_E_COYOTE\n" +
                     "Part_Number=Rocket_Launcher_0001\n" +
                     "Shipping=FedEx\n", res.body)
      }
    }
  end
end
