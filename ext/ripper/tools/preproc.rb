def main
  prelude
  grammar
  usercode
end

def prelude
  while line = ARGF.gets
    case line
    when %r</\*%%%\*/>
      puts '/*'
    when %r</\*%>
      puts '*/'
    when %r<%\*/>
      puts
    when /\A%%/
      puts '%%'
      return
    when /\A%token/
      puts line.sub(/<\w+>/, '<val>')
    when /\A%type/
      puts line.sub(/<\w+>/, '<val>')
    else
      print line
    end
  end
end

def grammar
  while line = ARGF.gets
    case line
    when %r</\*%%%\*/>
      puts '#if 0'
    when %r</\*%c%\*/>
      puts '/*'
    when %r</\*%c>
      puts '*/'
    when %r</\*%>
      puts '#endif'
    when %r<%\*/>
      puts
    when /\A%%/
      puts '%%'
      return
    else
      print line
    end
  end
end

def usercode
  while line = ARGF.gets
    print line
  end
end

main
