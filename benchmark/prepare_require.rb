require "fileutils"

def prepare
  num_files = 10000

  basename = File.dirname($0)
  data_dir = File.join(basename, "bm_require.data")

  # skip if all of files exists
  if File.exist?(File.join(data_dir, "c#{num_files}.rb"))
    return
  end

  FileUtils.mkdir_p(data_dir)

  1.upto(num_files) do |i|
    f = File.open("#{data_dir}/c#{i}.rb", "w")
    f.puts <<-END
      class C#{i}
      end
    END
  end
end

prepare
