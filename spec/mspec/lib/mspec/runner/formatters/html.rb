require 'mspec/runner/formatters/base'

class HtmlFormatter < BaseFormatter
  def register
    super
    MSpec.register :start, self
    MSpec.register :enter, self
    MSpec.register :leave, self
  end

  def start
    print <<-EOH
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN"
    "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
<title>Spec Output For #{RUBY_ENGINE} (#{RUBY_VERSION})</title>
<style type="text/css">
ul {
  list-style: none;
}
.fail {
  color: red;
}
.pass {
  color: green;
}
#details :target {
  background-color: #ffffe0;
}
</style>
</head>
<body>
EOH
  end

  def enter(describe)
    print "<div><p>#{describe}</p>\n<ul>\n"
  end

  def leave
    print "</ul>\n</div>\n"
  end

  def exception(exception)
    super(exception)
    outcome = exception.failure? ? "FAILED" : "ERROR"
    print %[<li class="fail">- #{exception.it} (<a href="#details-#{@count}">]
    print %[#{outcome} - #{@count}</a>)</li>\n]
  end

  def after(state = nil)
    super(state)
    print %[<li class="pass">- #{state.it}</li>\n] unless exception?
  end

  def finish
    success = @exceptions.empty?
    unless success
      print "<hr>\n"
      print %[<ol id="details">]
      count = 0
      @exceptions.each do |exc|
        outcome = exc.failure? ? "FAILED" : "ERROR"
        print %[\n<li id="details-#{count += 1}"><p>#{escape(exc.description)} #{outcome}</p>\n<p>]
        print escape(exc.message)
        print "</p>\n<pre>\n"
        print escape(exc.backtrace)
        print "</pre>\n</li>\n"
      end
      print "</ol>\n"
    end
    print %[<p>#{@timer.format}</p>\n]
    print %[<p class="#{success ? "pass" : "fail"}">#{@tally.format}</p>\n]
    print "</body>\n</html>\n"
  end

  def escape(string)
    string.gsub("&", "&nbsp;").gsub("<", "&lt;").gsub(">", "&gt;")
  end
end
