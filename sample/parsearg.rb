#
#		parseargs.rb - parse arguments
#			$Release Version: $
#			$Revision: 1.3 $
#			$Date: 1994/02/15 05:16:21 $
#			by Yasuo OHBA(STAFS Development Room)
#
# --
# 引数の解析をし, $OPT_?? に値をセットします. 
# 正常終了した場合は, セットされたオプションの数を返します. 
#
#    parseArgs(argc, single_opts, *opts)
#
#	ex. sample [options] filename
#	    options ...
#		-f -x --version --geometry 100x200 -d unix:0.0
#			    ↓
#	parseArgs(1, nil, "fx", "version", "geometry:", "d:")
#
#    第一引数: 
#	オプション以外の最低引数の数
#    第二引数: 
#	オプションの必要性…必ず必要なら %TRUE そうでなければ %FALSE.
#    第三引数: 
#	-f や -x (= -fx) の様な一文字のオプションの指定をします. 
#	ここで引数がないときは nil の指定が必要です. 
#    第四引数以降:
#	ロングネームのオプションや, 引数の伴うオプションの指定をします. 
#	--version や, --geometry 300x400 や, -d host:0.0 等です. 
#	引数を伴う指定は ":" を必ず付けてください. 
#
#    オプションの指定があった場合, 変数 $OPT_?? に non-nil もしくは, そのオ
#    プションの引数がセットされます. 
#	-f -> $OPT_f = %TRUE
#	--geometry 300x400 -> $OPT_geometry = 300x400
#
#    usage を使いたい場合は, $USAGE に usage() を指定します. 
#	def usage()
#	    …
#	end
#	$USAGE = 'usage'
#    usage は, --help が指定された時, 間違った指定をした時に表示します. 
#
#    - もしくは -- は, それ以降, 全てオプションの解析をしません. 
#

$RCS_ID="$Header: /var/ohba/RCS/parseargs.rb,v 1.3 1994/02/15 05:16:21 ohba Exp ohba $"

load("getopts.rb")

def printUsageAndExit()
  if $USAGE
    apply($USAGE)
  end
  exit()
end

def parseArgs(argc, nopt, single_opts, *opts)
  if ((noOptions = getopts(single_opts, *opts)) == nil)
    printUsageAndExit()
  end
  if (nopt && noOptions == 0)
    printUsageAndExit()
  end
  if ($ARGV.length < argc)
    printUsageAndExit()
  end
  return noOptions
end
