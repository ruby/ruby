def serb(str, var)
  result = ''
  str.each_line {|line|
    if /\A!/ =~ line
      result << $'
    else
      line.split(/(<%.*?%>)/).each {|x|
        if /\A<%(.*)%>\z/ =~ x
          result << "#{var} << (#{$1}).to_s\n"
        else
          result << "#{var} << #{x.dump}\n"
        end
      }
    end
  }
  result
end
