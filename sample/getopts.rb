#
#		getopts.rb - get options
#			$Release Version: $
#			$Revision: 1.2 $
#			$Date: 1994/02/15 05:17:15 $
#			by Yasuo OHBA(STAFS Development Room)
#
# --
# オプションの解析をし, $OPT_?? に値をセットします. 
# 指定のないオプションが指定された時は nil を返します.
# 正常終了した場合は, セットされたオプションの数を返します. 
#
#    getopts(single_opts, *opts)
#
#	ex. sample [options] filename
#	    options ...
#		-f -x --version --geometry 100x200 -d unix:0.0
#			    ↓
#	getopts("fx", "version", "geometry:", "d:")
#
#    第一引数: 
#	-f や -x (= -fx) の様な一文字のオプションの指定をします. 
#	ここで引数がないときは nil の指定が必要です. 
#    第二引数以降:
#	ロングネームのオプションや, 引数の伴うオプションの指定をします. 
#	--version や, --geometry 300x400 や, -d host:0.0 等です. 
#	引数を伴う指定は ":" を必ず付けてください. 
#
#    オプションの指定があった場合, 変数 $OPT_?? に non-nil もしくは, そのオ
#    プションの引数がセットされます. 
#	-f -> $OPT_f = %TRUE
#	--geometry 300x400 -> $OPT_geometry = 300x400
#
#    - もしくは -- は, それ以降, 全てオプションの解析をしません. 
#

$RCS_ID="$Header: /var/ohba/RCS/getopts.rb,v 1.2 1994/02/15 05:17:15 ohba Exp ohba $"

def getopts(single_opts, *opts)
  if (opts)
    single_colon = ""
    long_opts = []
    sc = 0
    for option in opts
      if (option.length <= 2)
	single_colon[sc, 0] = option[0, 1]
	sc += 1
      else
	long_opts.push(option)
      end
    end
  end
  
  count = 0
  while ($ARGV.length != 0)
    compare = nil
    case $ARGV[0]
    when /^-*$/
      $ARGV.shift
      break
    when /^--.*/
      compare = $ARGV[0][2, ($ARGV[0].length - 2)]
      if (long_opts != "")
        for option in long_opts
          if (option[(option.length - 1), 1] == ":" &&
              option[0, (option.length - 1)] == compare)
            if ($ARGV.length <= 1)
	      return nil
            end
            eval("$OPT_" + compare + " = " + '$ARGV[1]')
            $ARGV.shift
	    count += 1
	    break
          elsif (option == compare)
            eval("$OPT_" + compare + " = %TRUE")
	    count += 1
            break
          end
        end
      end
    when /^-.*/
      for index in 1..($ARGV[0].length - 1)
	compare = $ARGV[0][index, 1]
	if (single_opts && compare =~ "[" + single_opts + "]")
	  eval("$OPT_" + compare + " = %TRUE")
	  count += 1
	elsif (single_colon != "" && compare =~ "[" + single_colon + "]")
	  if ($ARGV[0][index..-1].length > 1)
	    eval("$OPT_" + compare + " = " + '$ARGV[0][(index + 1)..-1]')
	    count += 1
	  elsif ($ARGV.length <= 1)
	    return nil
	  else
	    eval("$OPT_" + compare + " = " + '$ARGV[1]')
	    $ARGV.shift
	    count = count + 1
	  end
	  break
	end
      end
    else
      break
    end

    $ARGV.shift
    if (!defined("$OPT_" + compare))
      return nil
    end
  end
  return count
end
