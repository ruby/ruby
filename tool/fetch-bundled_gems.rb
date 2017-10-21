require 'fileutils'

File.readlines("#{ARGV[0]}/gems/bundled_gems").each do |gem|
  n, v, u = gem.split

  v = "v" + v

  case n
  when "minitest"
    v = "master"
  when "test-unit"
    v = v[1..-1]
  end

  FileUtils.mkdir_p "#{ARGV[0]}/gems/src"
  `#{ARGV[0]}/tool/git-refresh -C #{ARGV[0]}/gems/src --branch #{v} #{u} #{n}`
end
