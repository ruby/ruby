# From https://bugs.ruby-lang.org/issues/13526#note-1

Thread.report_on_exception = true

sleep if $load
$load = true

n = 10
threads = Array.new(n) do
  Thread.new do
    begin
      autoload :Foo, File.expand_path(__FILE__)
      Thread.pass
      Foo
    ensure
      Thread.pass
    end
  end
end

Thread.pass until threads.all?(&:stop?)
1000.times { Thread.pass }
