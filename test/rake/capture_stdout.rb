require 'stringio'

# Mix-in for capturing standard output.
module CaptureStdout
  def capture_stdout
    s = StringIO.new
    oldstdout = $stdout
    $stdout = s
    yield
    s.string
  ensure
    $stdout = oldstdout
  end

  def capture_stderr
    s = StringIO.new
    oldstderr = $stderr
    $stderr = s
    yield
    s.string
  ensure
    $stderr = oldstderr
  end
end
