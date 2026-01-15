# frozen_string_literal: false
require_relative 'base'

class TestMkmfFindExecutable < TestMkmf
  def setup
    super
    @path, ENV["PATH"] = ENV["PATH"], @tmpdir
  end

  def each_exts(&block)
    name = "foobar#{$$}#{rand(1000)}"
    stdout.filter {|s| s.sub(name, "<executable>")}
    exts = mkmf {self.class::CONFIG['EXECUTABLE_EXTS']}.split
    exts[0] ||= ""
    exts.each do |ext|
      yield name+ext, name
    end
  end

  def teardown
    ENV["PATH"] = @path
    super
  end

  def test_find_executable
    bug2669 = '[ruby-core:27912]'
    each_exts do |full, name|
      begin
        open(full, "w") {|ff| ff.chmod(0755)}
        result = mkmf {find_executable(name)}
      ensure
        File.unlink(full)
      end
      assert_equal("#{@tmpdir}/#{full}", result, bug2669)
    end
  end

  def test_find_executable_dir
    each_exts do |full, name|
      begin
        Dir.mkdir(full)
        result = mkmf {find_executable(name)}
      ensure
        Dir.rmdir(full)
      end
      assert_nil(result)
    end
  end

  if /mingw|mswin/ =~ RUBY_PLATFORM
    def test_quoted_path_on_windows
      ENV["PATH"] = %["#{@tmpdir}"]
      test_find_executable
    end
  end
end
