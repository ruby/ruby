1000.times do |i|
	$stderr.puts i
	queue = Thread::Queue.new
	r, w = IO.pipe
	th = Thread.start do
		queue.push(nil)
		r.read 1
	end
	queue.pop
	th.kill
	th.join
end
