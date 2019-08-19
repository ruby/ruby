require "coverage"

Coverage.start(lines: true, branches: true, methods: true)

TEST_COVERAGE_DATA_FILE = "test-coverage.dat"

def merge_coverage_data(res1, res2)
  res1.each do |path, cov1|
    cov2 = res2[path]
    if cov2
      cov1[:lines].each_with_index do |count1, i|
        next unless count1
        add_count(cov2[:lines], i, count1)
      end
      cov1[:branches].each do |base_key, targets1|
        if cov2[:branches][base_key]
          targets1.each do |target_key, count1|
            add_count(cov2[:branches][base_key], target_key, count1)
          end
        else
          cov2[:branches][base_key] = targets1
        end
      end
      cov1[:methods].each do |key, count1|
        add_count(cov2[:methods], key, count1)
      end
    else
      res2[path] = cov1
    end
  end
  res2
end

def add_count(h, key, count)
  if h[key]
    h[key] += count
  else
    h[key] = count
  end
end

def save_coverage_data(res1)
  res1.each do |_path, cov|
    if cov[:methods]
      h = {}
      cov[:methods].each do |(klass, *key), count|
        h[[klass.inspect, *key]] = count
      end
      cov[:methods].replace h
    end
  end
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
  cur_dir = Dir.pwd

  res.each do |path, cov|
    next unless path.start_with?(base_dir) || path.start_with?(cur_dir)
    next if path.start_with?(File.join(base_dir, "test"))
    simplecov_result[path] = cov[:lines]
  end

  a, b = base_dir, cur_dir
  until a == b
    if a.size > b.size
      a = File.dirname(a)
    else
      b = File.dirname(b)
    end
  end
  root_dir = a

  SimpleCov.configure do
    root(root_dir)
    coverage_dir(File.join(cur_dir, "coverage"))
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
