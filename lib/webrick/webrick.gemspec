Gem::Specification.new do |s|
  s.name = "webrick"
  s.version = '0.0.1'
  s.date = '2017-01-30'
  s.summary = "HTTP server toolkit"
  s.description = "WEBrick is an HTTP server toolkit that can be configured as an HTTPS server, a proxy server, and a virtual-host server."

  s.require_path = %w{lib}
  s.files = %w{webrick.rb webrick/accesslog.rb webrick/cgi.rb webrick/compat.rb webrick/config.rb webrick/cookie.rb webrick/htmlutils.rb webrick/httpauth.rb webrick/httpauth/authenticator.rb webrick/httpauth/basicauth.rb webrick/httpauth/digestauth.rb webrick/httpauth/htdigest.rb webrick/httpauth/htgroup.rb webrick/httpauth/htpasswd.rb webrick/httpauth/userdb.rb webrick/httpauth.rb webrick/httpproxy.rb webrick/httprequest.rb webrick/httpresponse.rb webrick/https.rb webrick/httpserver.rb webrick/httpservlet.rb webrick/httpservlet/abstract.rb webrick/httpservlet/cgi_runner.rb webrick/httpservlet/cgihandler.rb webrick/httpservlet/erbhandler.rb webrick/httpservlet/filehandler.rb webrick/httpservlet/prochandler.rb webrick/httpservlet.rb webrick/httpstatus.rb webrick/httputils.rb webrick/httpversion.rb webrick/log.rb webrick/server.rb webrick/ssl.rb webrick/utils.rb webrick/version.rb}
  s.required_ruby_version = ">= 2.5.0dev"

  s.authors = ["TAKAHASHI Masayoshi", "GOTOU YUUZOU"]
  s.email = [nil, nil]
  s.homepage = "https://www.ruby-lang.org"
  s.license = "BSD-2-Clause"
end
