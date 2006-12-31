#!/usr/bin/env ruby
#
#

require 'rb/insns2vm.rb'
insns = insns_def_new

{ # docs
  '/doc/yarvarch.ja' => :desc_ja,
  '/doc/yarvarch.en' => :desc_en,
}.each{|fn, s|
  fn = $srcdir + fn
  p fn
  open(fn, 'w'){|f|
    f.puts(insns.__send__(s))
  }
}

def chg ary
  if ary.empty?
    return '&nbsp;'
  end
  
  ary.map{|e|
    if e[0] == '...'
      '...'
    else
      e.join(' ')
    end
    e[1]
  }.join(', ')
end

open($srcdir + '/doc/insnstbl.html', 'w'){|f|
  tbl = ''
  type = nil
  insns.each_with_index{|insn, i|
    c = insn.comm[:c]
    if type != c
      stype = c
      type  = c
    end
    
    tbl << "<tr>\n"
    tbl << "<td>#{stype}</td>"
    tbl << "<td>#{i}</td>"
    tbl << "<td>#{insn.name}</td>"
    tbl << "<td>#{chg insn.opes}</td>"
    tbl << "<td>#{chg insn.pops.reverse}</td>"
    tbl << "<td> =&gt; </td>"
    tbl << "<td>#{chg insn.rets.reverse}</td>"
    tbl << "</tr>\n"
  }
  f.puts ERB.new(File.read($srcdir + '/template/insnstbl.html')).result(binding)
}

begin
  system('t2n.bat --tmpl doc.tmpl ../doc/yarvarch.ja > ../doc/yarvarch.ja.html')
  system('t2n.bat --tmpl doc.tmpl ../doc/yarvarch.en > ../doc/yarvarch.en.html')
rescue
end

