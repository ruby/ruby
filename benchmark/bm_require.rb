$:.push File.join(File.dirname(__FILE__), "bm_require.data")

1.upto(10000) do |i|
  require "c#{i}"
end

$:.pop
