assert_equal '0', %q{
  begin
    GC.stress = true
    pid = fork {}
    Process.wait pid
    $?.to_i
  rescue NotImplementedError
    0
  end
}, '[ruby-dev:32404]'

assert_finish 10, %q{
  children = (1..10).map{
    Thread.start{fork{}}.value
  }
  while !children.empty? and pid = Process.wait
    children.delete(pid)
  end
}, '[ruby-core:22158]'
