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
