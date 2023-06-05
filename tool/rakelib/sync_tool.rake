task :sync_tool, [:from] do |t, from: nil|
  from ||= (File.identical?(__dir__, "rakelib") ? "../ruby/tool" : File.dirname(__dir__))

  require 'fileutils'

  {
    "rakelib/sync_tool.rake" => "rakelib",
    "lib/core_assertions.rb" => "test/lib",
    "lib/envutil.rb" => "test/lib",
    "lib/find_executable.rb" => "test/lib",
    "lib/helper.rb" => "test/lib",
  }.each do |src, dest|
    FileUtils.mkpath(dest)
    FileUtils.cp "#{from}/#{src}", dest
  rescue Errno::ENOENT
  end
end
