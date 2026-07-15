# RLGCv2: the object-traversal mark redirect is per Ractor
# (design_v2.md section 1.3). While main keeps a redirect installed
# (ObjectSpace.reachable_objects_from / _from_root), worker Ractors run
# local GCs concurrently: their real marks must never see main's
# redirect (the old VM-global field needed a during_gc gate; a miss
# meant feeding a foreign callback and freeing live objects). The
# callbacks here also allocate, so main's own GC can fire mid-traversal
# -- covered by parking the redirect around each callback.
# (ObjectSpace's traversal APIs are main-Ractor-only at the Ruby level,
# so the worker side of the API needs no testing.)
Warning[:experimental] = false
begin
  require "objspace"
rescue LoadError
  # in-tree run without ext load paths: re-exec with them. The .ext
  # tree lives next to the running binary (the BUILD dir -- not
  # necessarily this script's source dir, e.g. sanitizer builds).
  srcdir = File.expand_path("..", __dir__)
  builddir = File.dirname(File.readlink("/proc/self/exe")) rescue srcdir
  base = [builddir, srcdir].find { |d| Dir.exist?(File.join(d, ".ext")) }
  abort "objspace ext not built" unless base
  extdir = Dir[File.join(base, ".ext", "*-*")].reject { |d| d.end_with?("include") }.first
  abort "objspace ext not built" unless extdir
  exec "/proc/self/exe", "--disable-gems", "-I#{extdir}",
       "-I#{File.join(base, '.ext', 'common')}", "-I#{File.join(srcdir, 'lib')}",
       __FILE__, *ARGV
end

stop = Ractor::Port.new
workers = 6.times.map do |i|
  Ractor.new(stop, i) do |port, idx|
    n = 0
    loop do
      Array.new(500) { +"w#{idx}" }        # allocation churn -> local GCs
      GC.start(full_mark: (n % 7 == 0))
      n += 1
      break if n % 16 == 0 && port.closed?
    end
    n
  end
end

own = Array.new(400) { |i| { id: i, payload: +"m#{i}" * 4, link: [i, [i]] } }
total = 0
200.times do |round|
  node = own[round % own.size]
  seen = ObjectSpace.reachable_objects_from(node)   # redirect installed
  total += seen.size
  Array.new(300) { +"g" }                           # callback-adjacent churn
  if round % 50 == 0
    ObjectSpace.reachable_objects_from_root
    GC.verify_internal_consistency
  end
end

stop.close
counts = workers.map(&:value)
raise "workers idle" unless counts.all? { |c| c > 0 }
raise "traversals empty" unless total >= 200 * 2
GC.verify_internal_consistency
puts "REACHABLE_REDIRECT_OK"
