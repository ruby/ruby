require 'ripper/filter'

class ColorizeFilter < Ripper::Filter
  def on_default(event, tok, f)
    f << escape(tok)
  end

  def on_comment(tok, f)
    f << %Q[<span class="comment">#{escape(tok)}</span>]
  end

  def on_tstring_content(tok, f)
    f << %Q[<span class="string">#{escape(tok)}</span>]
  end

  ESC = {
    '&' => '&amp;',
    '<' => '&lt;',
    '>' => '&gt;'
  }

  def escape(str)
    tbl = ESC
    str.gsub(/[&<>]/) {|ch| tbl[ch] }
  end
end

if $0 == __FILE__
  ColorizeFilter.new(ARGF).parse($stdout)
end
