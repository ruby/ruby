require 'erb'

class ERB
  class ERBString < String
    def to_s; self; end

    def erb_concat(s)
      if self.class === s
        concat(s)
      else
        concat(erb_quote(s))
      end
    end

    def erb_quote(s); s; end
  end
end

class ERB4Html < ERB
  def self.quoted(s)
    HtmlString.new(s)
  end

  class HtmlString < ERB::ERBString
    def erb_quote(s)
      ERB::Util::html_escape(s)
    end
  end

  def set_eoutvar(compiler, eoutvar = '_erbout')
    compiler.put_cmd = "#{eoutvar}.concat"
    compiler.insert_cmd = "#{eoutvar}.erb_concat"

    cmd = []
    cmd.push "#{eoutvar} = ERB4Html.quoted('')"

    compiler.pre_cmd = cmd

    cmd = []
    cmd.push(eoutvar)

    compiler.post_cmd = cmd
  end
end

if __FILE__ == $0
  page = <<EOP
<title><%=title%></title>
<p><%=para%></p>
EOP
  erb = ERB4Html.new(page)

  title = "<auto-quote>"
  para = "&lt;quoted&gt;"
  puts erb.result

  title = "<auto-quote>"
  para = ERB4Html.quoted("&lt;quoted&gt;")
  puts erb.result
end
