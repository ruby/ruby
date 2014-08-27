require File.expand_path('../helper', __FILE__)

class TestRakeCpuCounter < Rake::TestCase

  def setup
    super

    @cpu_counter = Rake::CpuCounter.new
  end

  def test_count_via_win32
    if Rake::Win32.windows? then
      assert_kind_of Numeric, @cpu_counter.count_via_win32
    else
      assert_nil @cpu_counter.count_via_win32
    end
  end

  def test_in_path_command
    with_ruby_in_path do |ruby|
      assert_equal ruby, @cpu_counter.in_path_command(ruby)
    end
  rescue Errno::ENOENT => e
    raise unless e.message =~ /\bwhich\b/

    skip 'cannot find which for this test'
  end

  def test_run
    with_ruby_in_path do |ruby|
      assert_equal 7, @cpu_counter.run(ruby, '-e', 'puts 3 + 4')
    end
  end

  def with_ruby_in_path
    ruby     = File.basename Gem.ruby
    ruby_dir = File.dirname  Gem.ruby

    begin
      orig_path, ENV['PATH'] =
        ENV['PATH'], [ruby_dir, *ENV['PATH']].join(File::PATH_SEPARATOR)

      yield ruby
    ensure
      ENV['PATH'] = orig_path
    end
  end

end

