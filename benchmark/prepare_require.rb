require "fileutils"

basename = File.dirname($0)
data_dir = File.join(basename, "bm_require.data")

FileUtils.mkdir_p(data_dir)

1.upto(10000) do |i|
  f = File.open("#{data_dir}/c#{i}.rb", "w")
  f.puts <<-END
      class C#{i}
      end
    END
end
