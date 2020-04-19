# [ThreadGroup](ThreadGroup) provides a means of
# keeping track of a number of threads as a group.
# 
# A given [Thread](https://ruby-doc.org/core-2.6.3/Thread.html) object can
# only belong to one [ThreadGroup](ThreadGroup) at a
# time; adding a thread to a new group will remove it from any previous
# group.
# 
# Newly created threads belong to the same group as the thread from which
# they were created.
class ThreadGroup < Object
  def add: (Thread thread) -> ThreadGroup

  def enclose: () -> ThreadGroup

  # Returns `true` if the `thgrp` is enclosed. See also
  # [\#enclose](ThreadGroup.downloaded.ruby_doc#method-i-enclose).
  def enclosed?: () -> bool

  def list: () -> ::Array[Thread]
end

ThreadGroup::Default: ThreadGroup
