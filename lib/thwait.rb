#
#   thwait.rb - スレッド同期クラス
#   	$Release Version: 0.9 $
#   	$Revision: 1.3 $
#   	$Date: 1998/06/26 03:19:34 $
#   	by Keiju ISHITSUKA(Nihpon Rational Software Co.,Ltd.)
#
# --
#  機能:
#  複数のスレッドを関しそれらのスレッドが終了するまでwaitする機能を提
#  供する. 
#
#  クラスメソッド:
#  * ThreadsWait.all_waits(thread1,...)
#    全てのスレッドが終了するまで待つ. イテレータとして呼ばれた時には, 
#    スレッドが終了する度にイテレータを実行する.
#  * th = ThreadsWait.new(thread1,...)
#    同期するスレッドを指定し同期オブジェクトを生成.
#  
#  メソッド:
#  * th.threads
#    同期すべきスレッドの一覧
#  * th.empty?
#    同期すべきスレッドがあるかどうか
#  * th.finished?
#    すでに終了したスレッドがあるかどうか
#  * th.join(thread1,...) 
#    同期するスレッドを指定し, いずれかのスレッドが終了するまで待ちにはいる.
#  * th.join_nowait(threa1,...)
#    同期するスレッドを指定する. 待ちには入らない.
#  * th.next_wait
#    いずれかのスレッドが終了するまで待ちにはいる.
#  * th.all_waits
#    全てのスレッドが終了するまで待つ. イテレータとして呼ばれた時には, 
#    スレッドが終了する度にイテレータを実行する.
#

require "thread.rb"
require "e2mmap.rb"

class ThreadsWait
  RCS_ID='-$Id: thwait.rb,v 1.3 1998/06/26 03:19:34 keiju Exp keiju $-'
  
  Exception2MessageMapper.extend_to(binding)
  def_exception("ErrNoWaitingThread", "No threads for waiting.")
  def_exception("ErrNoFinshedThread", "No finished threads.")
  
  # class mthods
  #	all_waits
  
  #
  # 指定したスレッドが全て終了するまで待つ. イテレータとして呼ばれると
  # 指定したスレッドが終了するとその終了したスレッドを引数としてイテレー
  # タを呼び出す. 
  #
  def ThreadsWait.all_waits(*threads)
    tw = ThreadsWait.new(*threads)
    if iterator?
      tw.all_waits do
	|th|
	yield th
      end
    else
      tw.all_waits
    end
  end
  
  # initialize and terminating:
  #	initialize
  
  #
  # 初期化. 待つスレッドの指定ができる.
  #
  def initialize(*threads)
    @threads = []
    @wait_queue = Queue.new
    join_nowait(*threads) unless threads.empty?
  end
  
  # accessing
  #	threads
  
  # 待ちスレッドの一覧を返す.
  attr :threads
  
  # testing
  #	empty?
  #	finished?
  #
  
  #
  # 待ちスレッドが存在するかどうかを返す.
  def empty?
    @threads.empty?
  end
  
  #
  # すでに終了したスレッドがあるかどうか返す
  def finished?
    !@wait_queue.empty?
  end
  
  # main process:
  #	join
  #	join_nowait
  #	next_wait
  #	all_wait
  
  #
  # 待っているスレッドを追加し. いずれかのスレッドが1つ終了するまで待
  # ちにはいる.
  #
  def join(*threads)
    join_nowait(*threads)
    next_wait
  end
  
  #
  # 待っているスレッドを追加する. 待ちには入らない.
  #
  def join_nowait(*threads)
    @threads.concat threads
    for th in threads
      Thread.start do
	th = Thread.join(th)
	@wait_queue.push th
      end
    end
  end
  
  #
  # いずれかのスレッドが終了するまで待ちにはいる.
  # 待つべきスレッドがなければ, 例外ErrNoWaitingThreadを返す.
  # nonnlockが真の時には, nonblockingで調べる. 存在しなければ, 例外
  # ErrNoFinishedThreadを返す.
  #
  def next_wait(nonblock = nil)
    ThreadsWait.fail ErrNoWaitingThread if @threads.empty?
    begin
      @threads.delete(th = @wait_queue.pop(nonblock))
      th
    rescue ThreadError
      ThreadsWait.fail ErrNoFinshedThread
    end
  end
  
  #
  # 全てのスレッドが終了するまで待つ. イテレータとして呼ばれた時は, ス
  # レッドが終了する度に, イテレータを呼び出す.
  #
  def all_waits
    until @threads.empty?
      th = next_wait
      yield th if iterator?
    end
  end
end

ThWait = ThreadsWait
