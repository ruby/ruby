line = ''
indent=0
print "ruby> "
while TRUE
  l = gets
  if not l
    break if line == ''
  else
    line = line + l 
    if l =~ /,\s*$/
      print "ruby| "
      next
    end
    if l =~ /^\s*(class|module|def|if|case|while|for|begin)\b[^_]/
      indent += 1
    end
    if l =~ /^\s*end\b[^_]/
      indent -= 1
    end
    if l =~ /{\s*(\|.*\|)?\s*$/
      indent += 1
    end
    if l =~ /^\s*\}/
      indent -= 1
    end
    if indent > 0
      print "ruby| "
      next
    end
  end
  begin
    print eval(line).inspect, "\n"
  rescue
    $! = 'exception raised' if not $!
    print "ERR: ", $!, "\n"
  end
  break if not l
  line = ''
  print "ruby> "
end
print "\n"
