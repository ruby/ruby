# tof

#### tcltk ライブラリ
####	Sep. 5, 1997	Y. Shigehiro

require "tcltklib"

################

# module TclTk: tcl/tk のライブラリ全体で必要になるものを集めたもの
# (主に, 名前空間の点から module にする使う.)
module TclTk

  # 単にここに書けば最初に 1 度実行されるのか??

  # 生成した一意な名前を保持しておく連想配列を初期化する.
  @namecnt = {}

  # コールバックを保持しておく連想配列を初期化する.
  @callback = {}
end

# TclTk.mainloop(): TclTkLib.mainloop() を呼ぶ.
def TclTk.mainloop()
  print("mainloop: start\n") if $DEBUG
  TclTkLib.mainloop()
  print("mainloop: end\n") if $DEBUG
end

# TclTk.deletecallbackkey(ca): コールバックを TclTk module から取り除く.
#     tcl/tk インタプリタにおいてコールバックが取り消されるわけではない.
#     これをしないと, 最後に TclTkInterpreter が GC できない.
#     (GC したくなければ, 別に, これをしなくても良い.)
#   ca: コールバック(TclTkCallback)
def TclTk.deletecallbackkey(ca)
  print("deletecallbackkey: ", ca.to_s(), "\n") if $DEBUG
  @callback.delete(ca.to_s)
end

# TclTk.dcb(ca, wid, W): 配列に入っている複数のコールバックに対して
#     TclTk.deletecallbackkey() を呼ぶ.
#     トップレベルの <Destroy> イベントのコールバックとして呼ぶためのもの.
#   ca: コールバック(TclTkCallback) の Array
#   wid: トップレベルのウィジェット(TclTkWidget)
#   w: コールバックに %W で与えられる, ウインドウに関するパラメータ(String)
def TclTk.dcb(ca, wid, w)
  if wid.to_s() == w
    ca.each{|i|
      TclTk.deletecallbackkey(i)
    }
  end
end

# TclTk._addcallback(ca): コールバックを登録する.
#   ca: コールバック(TclTkCallback)
def TclTk._addcallback(ca)
  print("_addcallback: ", ca.to_s(), "\n") if $DEBUG
  @callback[ca.to_s()] = ca
end

# TclTk._callcallback(key, arg): 登録したコールバックを呼び出す.
#   key: コールバックを選択するキー (TclTkCallback が to_s() で返す値)
#   arg: tcl/tk インタプリタからのパラメータ
def TclTk._callcallback(key, arg)
  print("_callcallback: ", @callback[key].inspect, "\n") if $DEBUG
  @callback[key]._call(arg)
  # コールバックからの返り値はどうせ捨てられる.
  # String を返さないと, rb_eval_string() がエラーになる.
  return ""
end

# TclTk._newname(prefix): 一意な名前(String)を生成して返す.
#   prefix: 名前の接頭語
def TclTk._newname(prefix)
  # 生成した名前のカウンタは @namecnt に入っているので, 調べる.
  if !@namecnt.key?(prefix)
    # 初めて使う接頭語なので初期化する.
    @namecnt[prefix] = 1
  else
    # 使ったことのある接頭語なので, 次の名前にする.
    @namecnt[prefix] += 1
  end
  return "#{prefix}#{@namecnt[prefix]}"
end

################

# class TclTkInterpreter: tcl/tk のインタプリタ
class TclTkInterpreter

  # initialize(): 初期化.
  def initialize()
    # インタプリタを生成する.
    @ip = TclTkIp.new()

    # インタプリタに ruby_fmt コマンドを追加する.
    # ruby_fmt コマンドとは, 後ろの引数を format コマンドで処理して
    # ruby コマンドに渡すものである.
    # (なお, ruby コマンドは, 引数を 1 つしかとれない.)
    if $DEBUG
      @ip._eval("proc ruby_fmt {fmt args} { puts \"ruby_fmt: $fmt $args\" ; ruby [format $fmt $args] }")
    else
      @ip._eval("proc ruby_fmt {fmt args} { ruby [format $fmt $args] }")
    end

    # @ip._get_eval_string(*args): tcl/tk インタプリタで評価する
    #     文字列(String)を生成して返す.
    #   *args: tcl/tk で評価するスクリプト(に対応するオブジェクト列)
    def @ip._get_eval_string(*args)
      argstr = ""
      args.each{|arg|
	argstr += " " if argstr != ""
	# もし to_eval() メソッドが
	if (arg.respond_to?(:to_eval))
	  # 定義されていればそれを呼ぶ.
	  argstr += arg.to_eval()
	else
	  # 定義されていなければ to_s() を呼ぶ.
	  argstr += arg.to_s()
	end
      }
      return argstr
    end

    # @ip._eval_args(*args): tcl/tk インタプリタで評価し,
    #     その結果(String)を返す.
    #   *args: tcl/tk で評価するスクリプト(に対応するオブジェクト列)
    def @ip._eval_args(*args)
      # インタプリタで評価する文字列を求める.
      argstr = _get_eval_string(*args)

      # インタプリタで評価する.
      print("_eval: \"", argstr, "\"") if $DEBUG
      res = _eval(argstr)
      if $DEBUG
	print(" -> \"", res, "\"\n")
      elsif  _return_value() != 0
	print(res, "\n")
      end
      fail(%Q/can't eval "#{argstr}"/) if _return_value() != 0
      return res
    end

    # tcl/tk のコマンドに対応するオブジェクトを生成し, 連想配列に入れておく.
    @commands = {}
    # tcl/tk インタプリタに登録されているすべてのコマンドに対して,
    @ip._eval("info command").split(/ /).each{|comname|
      if comname =~ /^[.]/
	# コマンドがウィジェット(のパス名)の場合は
	# TclTkWidget のインスタンスを作って連想配列に入れる.
	@commands[comname] = TclTkWidget.new(@ip, comname)
      else
	# そうでない場合は
	# TclTkCommand のインスタンスを作って連想配列に入れる.
	@commands[comname] = TclTkCommand.new(@ip, comname)
      end
    }
  end

  # commands(): tcl/tk のコマンドに対応するオブジェクトを Hash に
  #     入れたものを返す.
  def commands()
    return @commands
  end

  # rootwidget(): ルートウィジェット(TclTkWidget)を返す.
  def rootwidget()
    return @commands["."]
  end

  # _tcltkip(): @ip(TclTkIp) を返す.
  def _tcltkip()
    return @ip
  end

  # method_missing(id, *args): 未定義のメソッドは tcl/tk のコマンドとみなして
  #     実行し, その結果(String)を返す.
  #   id: メソッドのシンボル
  #   *args: コマンドの引数
  def method_missing(id, *args)
    # もし, メソッドの tcl/tk コマンドが
    if @commands.key?(id.id2name)
      # あれば, 実行して結果を返す.
      return @commands[id.id2name].e(*args)
    else
      # 無ければもともとの処理.
      super
    end
  end
end

# class TclTkObject: tcl/tk のオブジェクト
# (基底クラスとして使う.
#  tcltk ライブラリを使う人が TclTkObject.new() することはないはず.)
class TclTkObject

  # initialize(ip, exp): 初期化.
  #   ip: インタプリタ(TclTkIp)
  #   exp: tcl/tk での表現形
  def initialize(ip, exp)
    fail("type is not TclTkIp") if !ip.kind_of?(TclTkIp)
    @ip = ip
    @exp = exp
  end

  # to_s(): tcl/tk での表現形(String)を返す.
  def to_s()
    return @exp
  end
end

# class TclTkCommand: tcl/tk のコマンド
# (tcltk ライブラリを使う人が TclTkCommand.new() することはないはず.
#  TclTkInterpreter:initialize() から new() される.)
class TclTkCommand < TclTkObject

  # e(*args): コマンドを実行し, その結果(String)を返す.
  #     (e は exec または eval の e.)
  #   *args: コマンドの引数
  def e(*args)
    return @ip._eval_args(to_s(), *args)
  end
end

# class TclTkLibCommand: tcl/tk のコマンド
# (ライブラリにより実現されるコマンドで, tcl/tk インタプリタに最初から
#  存在しないものは, インタプリタの commands() では生成できない.
#  そのようなものに対し, コマンドの名前から TclTkCommand オブジェクトを
#  生成する.
class TclTkLibCommand < TclTkCommand

  # initialize(ip, name): 初期化
  #   ip: インタプリタ(TclTkInterpreter)
  #   name: コマンド名 (String)
  def initialize(ip, name)
    super(ip._tcltkip, name)
  end
end

# class TclTkVariable: tcl/tk の変数
class TclTkVariable < TclTkObject

  # initialize(interp, dat): 初期化.
  #   interp: インタプリタ(TclTkInterpreter)
  #   dat: 設定する値(String)
  #       nil なら, 設定しない.
  def initialize(interp, dat)
    # tcl/tk での表現形(変数名)を自動生成する.
    exp = TclTk._newname("v_")
    # TclTkObject を初期化する.
    super(interp._tcltkip(), exp)
    # set コマンドを使うのでとっておく.
    @set = interp.commands()["set"]
    # 値を設定する.
    set(dat) if dat
  end

  # tcl/tk の set を使えば, 値の設定/参照はできるが,
  # それだけではなんなので, 一応, メソッドをかぶせたものも用意しておく.

  # set(data): tcl/tk の変数に set を用いて値を設定する.
  #   data: 設定する値
  def set(data)
    @set.e(to_s(), data.to_s())
  end

  # get(): tcl/tk の変数の値(String)を set を用いて読みだし返す.
  def get()
    return @set.e(to_s())
  end
end

# class TclTkWidget: tcl/tk のウィジェット
class TclTkWidget < TclTkCommand

  # initialize(*args): 初期化.
  #   *args: パラメータ
  def initialize(*args)
    if args[0].kind_of?(TclTkIp)
      # 最初の引数が TclTkIp の場合:

      # 既に tcl/tk に定義されているウィジェットに TclTkWidget の構造を
      # かぶせる. (TclTkInterpreter:initialize() から使われる.)

      # パラメータ数が 2 でなければエラー.
      fail("illegal # of parameter") if args.size != 2

      # ip: インタプリタ(TclTkIp)
      # exp: tcl/tk での表現形
      ip, exp = args

      # TclTkObject を初期化する.
      super(ip, exp)
    elsif args[0].kind_of?(TclTkInterpreter)
      # 最初の引数が TclTkInterpreter の場合:

      # 親ウィジェットから新たなウィジェトを生成する.

      # interp: インタプリタ(TclTkInterpreter)
      # parent: 親ウィジェット
      # command: ウィジェットを生成するコマンド(label 等)
      # *args: command に渡す引数
      interp, parent, command, *args = args

      # ウィジェットの名前を作る.
      exp = parent.to_s()
      exp += "." if exp !~ /[.]$/
      exp += TclTk._newname("w_")
      # TclTkObject を初期化する.
      super(interp._tcltkip(), exp)
      # ウィジェットを生成する.
      res = @ip._eval_args(command, exp, *args)
#      fail("can't create Widget") if res != exp
      # tk_optionMenu では, ボタン名を exp で指定すると
      # res にメニュー名を返すので res != exp となる.
    else
      fail("first parameter is not TclTkInterpreter")
    end
  end
end

# class TclTkCallback: tcl/tk のコールバック
class TclTkCallback < TclTkObject

  # initialize(interp, pr, arg): 初期化.
  #   interp: インタプリタ(TclTkInterpreter)
  #   pr: コールバック手続き(Proc)
  #   arg: pr のイテレータ変数に渡す文字列
  #       tcl/tk の bind コマンドではパラメータを受け取るために % 置換を
  #       用いるが, pr の内部で % を書いてもうまくいかない.
  #       arg に文字列を書いておくと, その置換結果を, pr で
  #       イテレータ変数を通して受け取ることができる.
  #       scrollbar コマンドの -command オプションのように
  #       何も指定しなくてもパラメータが付くコマンドに対しては,
  #       arg を指定してはならない.
  def initialize(interp, pr, arg = nil)
    # tcl/tk での表現形(変数名)を自動生成する.
    exp = TclTk._newname("c_")
    # TclTkObject を初期化する.
    super(interp._tcltkip(), exp)
    # パラメータをとっておく.
    @pr = pr
    @arg = arg
    # モジュールに登録しておく.
    TclTk._addcallback(self)
  end

  # to_eval(): @ip._eval_args で評価するときの表現形(String)を返す.
  def to_eval()
    if @arg
      # %s は ruby_fmt より前に bind により置換されてしまうので
      # %%s としてある. したがって, これは bind 専用.
      s = %Q/{ruby_fmt {TclTk._callcallback("#{to_s()}", "%%s")} #{@arg}}/
    else
      s = %Q/{ruby_fmt {TclTk._callcallback("#{to_s()}", "%s")}}/
    end

    return s
  end

  # _call(arg): コールバックを呼び出す.
  #   arg: コールバックに渡されるパラメータ
  def _call(arg)
    @pr.call(arg)
  end
end

# class TclTkImage: tcl/tk のイメージ
class TclTkImage < TclTkCommand

  # initialize(interp, t, *args): 初期化.
  #     イメージの生成は TclTkImage.new() で行うが,
  #     破壊は image delete で行う. (いまいちだけど仕方が無い.)
  #   interp: インタプリタ(TclTkInterpreter)
  #   t: イメージのタイプ (photo, bitmap, etc.)
  #   *args: コマンドの引数
  def initialize(interp, t, *args)
    # tcl/tk での表現形(変数名)を自動生成する.
    exp = TclTk._newname("i_")
    # TclTkObject を初期化する.
    super(interp._tcltkip(), exp)
    # イメージを生成する.
    res = @ip._eval_args("image create", t, exp, *args)
    fail("can't create Image") if res != exp
  end
end

# eof
