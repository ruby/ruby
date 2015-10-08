$:.push File.join(File.dirname(__FILE__), "bm_require.data")

i=0
t = Thread.new do
  while true
    i = i+1 # dummy loop
  end
end

1.upto(100) do |i|
  require "c#{i}"
end

$:.pop
t.kill
