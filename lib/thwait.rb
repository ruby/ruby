#
#   thwait.rb - thread synchronization class
#   	$Release Version: 0.9 $
#   	$Revision: 1.3 $
#   	$Date: 1998/06/26 03:19:34 $
#   	by Keiju ISHITSUKA(Nihpon Rational Software Co.,Ltd.)
#
# --
#  feature:
#  provides synchronization for multiple threads.
#
#  class methods:
#  * ThreadsWait.all_waits(thread1,...)
#    waits until all of specified threads are terminated.
#    if a block is supplied for the method, evaluates it for
#    each thread termination.
#  * th = ThreadsWait.new(thread1,...)
#    creates synchronization object, specifying thread(s) to wait.
#  
#  methods:
#  * th.threads
#    list threads to be synchronized
#  * th.empty?
#    is there any thread to be synchronized.
#  * th.finished?
#    is there already terminated thread.
#  * th.join(thread1,...) 
#    wait for specified thread(s).
#  * th.join_nowait(threa1,...)
#    specifies thread(s) to wait.  non-blocking.
#  * th.next_wait
#    waits until any of specified threads is terminated.
#  * th.all_waits
#    waits until all of specified threads are terminated.
#    if a block is supplied for the method, evaluates it for
#    each thread termination.
#

require "thread.rb"
require "e2mmap.rb"

class ThreadsWait
  RCS_ID='-$Id: thwait.rb,v 1.3 1998/06/26 03:19:34 keiju Exp keiju $-'
  
  Exception2MessageMapper.extend_to(binding)
  def_exception("ErrNoWaitingThread", "No threads for waiting.")
  def_exception("ErrNoFinshedThread", "No finished threads.")
  
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
  
  def initialize(*threads)
    @threads = []
    @wait_queue = Queue.new
    join_nowait(*threads) unless threads.empty?
  end
  
  # accessing
  #	threads - list threads to be synchronized
  attr :threads
  
  # testing
  #	empty?
  #	finished?

  # is there any thread to be synchronized.
  def empty?
    @threads.empty?
  end
  
  # is there already terminated thread.
  def finished?
    !@wait_queue.empty?
  end
  
  # main process:
  #	join
  #	join_nowait
  #	next_wait
  #	all_wait
  
  # adds thread(s) to join,  waits for any of waiting threads to terminate.
  def join(*threads)
    join_nowait(*threads)
    next_wait
  end
  
  # adds thread(s) to join, no wait.
  def join_nowait(*threads)
    @threads.concat threads
    for th in threads
      Thread.start do
	th = th.join
	@wait_queue.push th
      end
    end
  end
  
  # waits for any of waiting threads to terminate
  # if there is no thread to wait, raises ErrNoWaitingThread.
  # if `nonblock' is true, and there is no terminated thread,
  # raises ErrNoFinishedThread.
  def next_wait(nonblock = nil)
    ThreadsWait.fail ErrNoWaitingThread if @threads.empty?
    begin
      @threads.delete(th = @wait_queue.pop(nonblock))
      th
    rescue ThreadError
      ThreadsWait.fail ErrNoFinshedThread
    end
  end
  
  # waits until all of specified threads are terminated.
  # if a block is supplied for the method, evaluates it for
  # each thread termination.
  def all_waits
    until @threads.empty?
      th = next_wait
      yield th if iterator?
    end
  end
end

ThWait = ThreadsWait
