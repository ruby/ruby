# RLGCv2 (review A-4): moving an IO must carry the fptr's VALUE members
# (pathv, encs.ecopts, writeconv_pre_ecopts, ...) through the courier.
#
# The fptr rides across by pointer; before the fix its VALUE members kept
# pointing at sender-objspace objects that nothing rooted once the source
# was husked -- the sender's next local GC collected them under the
# receiver, and File#path / #inspect read freed memory (a File ALWAYS has
# a pathv, so "sound for simple IOs" never held).
Warning[:experimental] = false

40.times do |i|
  path = "/tmp/rlgc_mvio_#{$$}_#{i}"
  File.open(path, "w") { |w| w.write("hello #{i}") }

  # a File with encoding options => pathv + ecopts ride the courier
  f = File.open(path, "r:UTF-8")

  r = Ractor.new do
    io = Ractor.receive
    sleep 0.01           # let the sender GC first
    [io.path, io.read, io.inspect.size > 0]
  end
  r.send(f, move: true)

  # kill the (formerly ride-along) sender-side originals
  GC.start
  1000.times { "churn" * 8 }
  GC.start

  got_path, got_data, got_inspect = r.value
  raise "path corrupted: #{got_path.inspect}" unless got_path == path
  raise "data corrupted" unless got_data == "hello #{i}"
  raise "inspect broken" unless got_inspect
  File.unlink(path) rescue nil
end

# tied IO (popen r+) must be rejected up front, graph intact
r2 = Ractor.new { Ractor.receive }
io = IO.popen("cat", "r+")
begin
  r2.send(io, move: true)
  raise "tied move unexpectedly succeeded"
rescue Ractor::Error => e
  raise "wrong error: #{e.message}" unless e.message =~ /tied|can not move/
end
io.puts "still-usable"; io.close_write
raise "source io broken after failed move" unless io.read.strip == "still-usable"
io.close
r2.send(:done); r2.value

GC.start
GC.verify_internal_consistency
puts "OK v2_move_io_fields"
