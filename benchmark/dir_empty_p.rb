require 'tmpdir'
max = 100_000
Dir.mktmpdir('bm_dir_empty_p') do |dir|
  max.times { Dir.empty?(dir) }
end
