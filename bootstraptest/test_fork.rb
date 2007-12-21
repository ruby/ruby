assert_equal '0', %q{
  GC.stress = true
  pid = fork {}
  Process.wait pid
  $?.to_i
}, '[ruby-dev:32404]'
