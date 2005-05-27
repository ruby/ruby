#!ruby -d
require "webrick/cgi"

class TestApp < WEBrick::CGI
  def do_GET(req, res)
    res["content-type"] = "text/plain"
    if (p = req.path_info) && p.length > 0
      res.body = p
    elsif (q = req.query).size > 0
      res.body = q.keys.sort.collect{|key|
        q[key].list.sort.collect{|v|
          "#{key}=#{v}"
        }.join(", ")
      }.join(", ")
    elsif %r{/$} =~ req.request_uri.to_s
      res.body = ""
      res.body << req.request_uri.to_s  << "\n"
      res.body << req.script_name
    else
      res.body = req.script_name
    end
  end

  def do_POST(req, res)
    do_GET(req, res)
  end
end

cgi = TestApp.new
cgi.start
