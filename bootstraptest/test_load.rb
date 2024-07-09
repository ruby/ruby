assert_equal 'ok', %q{
  File.write("require-lock-test.rb", <<-END)
    sleep 0.1
    module M
    end
  END
  $:.unshift Dir.pwd
  vs = (1..2).map {|i|
    Thread.start {
      require "require-lock-test"
      M
    }
  }.map {|t| t.value }
  vs[0] == M && vs[1] == M ? :ok : :ng
}, '[ruby-dev:32048]' unless ENV.fetch('RUN_OPTS', '').include?('rjit') # Thread seems to be switching during JIT. To be fixed later.

assert_equal 'ok', %q{
  %w[a a/foo b].each {|d| Dir.mkdir(d)}
  File.write("b/foo", "$ok = :ok\n")
  $:.replace(%w[a b])
  begin
    load "foo"
    $ok
  rescue => e
    e.message
  end
}, '[ruby-dev:38097]'
