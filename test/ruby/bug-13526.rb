# From https://bugs.ruby-lang.org/issues/13526#note-1

sleep if $load
$load = true

n = 10
threads = Array.new(n) do
  Thread.new do
    begin
      autoload :Foo, "#{File.dirname($0)}/#{$0}"
      Thread.pass
      Foo
    ensure
      Thread.pass
    end
  end
end

Thread.pass while threads.all?(&:stop?)
100.times { Thread.pass }
