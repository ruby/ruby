# RLGCv2 design decision 9: at VM shutdown (rb_ractor_terminate_all)
# main inherits every dead, unjoined Ractor's objspace, so the at-exit
# passes behave as if there had always been one objspace. Probed here
# through IO flush: a Ractor leaves buffered data in an unclosed File
# and dies unjoined; the at-exit finalize pass must flush it (master
# parity). Without the shutdown absorb the zombie objspace is skipped
# and the data is lost.
#
# Self-contained (no stdlib): re-execs itself as the child that exits
# with the unflushed buffer, then checks the file content.

if ARGV[0] == "--child"
  path = ARGV[1]
  r = Ractor.new(path) do |p|
    f = File.open(p, "w")
    f.write "DATA-FROM-DEAD-RACTOR"
    :done # no close, no flush; die unjoined
  end
  sleep 0.1 until r.inspect.include?("terminated")
  $r = r # keep the Ractor object alive: no orphan path either
else
  ruby = ENV["RUBY"] || File.readlink("/proc/self/exe")
  path = "/tmp/rlgc_v2_flush_#{Process.pid}.out"
  begin
    system(ruby, __FILE__, "--child", path, err: File::NULL) or abort "child failed"
    content = File.read(path)
    abort "FLUSH LOST: #{content.inspect}" unless content == "DATA-FROM-DEAD-RACTOR"
    puts "OK"
  ensure
    File.unlink(path) rescue nil
  end
end
