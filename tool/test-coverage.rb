require "coverage"

Coverage.start

TEST_COVERAGE_DATA_FILE = "test-coverage.dat"

def merge_coverage_data(res1, res2)
  res1.each do |path, cov1|
    cov2 = res2[path]
    if cov2
      cov1.each_with_index do |count1, i|
        next unless count1
        if cov2[i]
          cov2[i] += count1
        else
          cov2[i] = count1
        end
      end
    else
      res2[path] = cov1
    end
  end
  res2
end

def save_coverage_data(res1)
  File.open(TEST_COVERAGE_DATA_FILE, File::RDWR | File::CREAT | File::BINARY) do |f|
    f.flock(File::LOCK_EX)
    s = f.read
    res2 = s.size > 0 ? Marshal.load(s) : {}
    res1 = merge_coverage_data(res1, res2)
    f.rewind
    f << Marshal.dump(res2)
    f.flush
    f.truncate(f.pos)
  end
end

def invoke_simplecov_formatter
  %w[doclie simplecov-html simplecov].each do |f|
    $LOAD_PATH.unshift "#{__dir__}/../coverage/#{f}/lib"
  end

  require "simplecov"
  res = Marshal.load(File.binread(TEST_COVERAGE_DATA_FILE))
  simplecov_result = {}
  base_dir = File.dirname(__dir__)

  res.each do |path, cov|
    next unless path.start_with?(base_dir)
    next if path.start_with?(File.join(base_dir, "test"))
    simplecov_result[path] = cov
  end

  res = SimpleCov::Result.new(simplecov_result)
  res.command_name = "Ruby's `make test-all`"
  SimpleCov::Formatter::HTMLFormatter.new.format(res)
end

pid = $$
pwd = Dir.pwd

at_exit do
  exit_exc = $!

  Dir.chdir(pwd) do
    save_coverage_data(Coverage.result)
    if pid == $$
      begin
        nil while Process.waitpid(-1)
      rescue Errno::ECHILD
        invoke_simplecov_formatter
      end
    end
  end

  raise exit_exc if exit_exc
end
