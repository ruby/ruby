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
  begin
    children = (1..10).map{
      Thread.start{fork{}}.value
    }
    while !children.empty? and pid = Process.wait
      children.delete(pid)
    end
  rescue NotImplementedError
  end
}, '[ruby-core:22158]'

assert_normal_exit(<<'End', '[ruby-dev:37934]')
  Thread.new { sleep 1; Thread.kill Thread.main }
  Process.setrlimit(:NPROC, 1)
  fork {}
End
