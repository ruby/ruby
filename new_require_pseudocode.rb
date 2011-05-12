gem 'minitest'
require 'minitest/unit'
require 'minitest/autorun'

$loaded_files = []
$new_load_path = []
$files = []
$cwd = "/cwd"

# Returns expanded path if loaded, otherwise nil
def new_require(file_name)
  file_to_load = if relative_path?(file_name)
    find_file_relative(file_name)
  else
    find_file_in_load_path(file_name)
  end

  if file_to_load && !$loaded_files.include?(file_to_load.downcase)
    $loaded_files.push(file_to_load.downcase)
    file_to_load
  end
end

def relative_path?(file_name)
  file_name[0] == ?.
end

def find_file_relative(file_name)
  file_name = File.expand_path(file_name, $cwd)
  possible_extensions(file_name).each do |ext|
    expanded_file_name = file_name + ext
    return expanded_file_name if file_exists?(expanded_file_name)
  end
end

def find_file_in_load_path(file_name)
  $new_load_path.each do |directory|
    directory = File.expand_path(directory)
    possible_extensions(file_name).each do |ext|
      expanded_file_name = directory + '/' + file_name + ext
      return expanded_file_name if file_exists?(expanded_file_name)
    end
  end

  nil
end

def file_exists?(expanded_file_name)
  $files.include?(expanded_file_name)
end

def possible_extensions(file_name)
  ext = File.extname(file_name)
  if ext == ""
    [".rb", ".so", ""]
  else
    [""]
  end
end

class RequireTest < MiniTest::Unit::TestCase
  def r(*args)
    new_require(*args)
  end

  def setup
    $file = []
    $new_load_path = []
    $loaded_files = []
  end

  def set_load_path(paths)
    $new_load_path = paths
  end

  def set_files(files)
    $files = files
  end

  def test_require_file_from_load_path
    set_load_path %w(/root)
    set_files %w(/root/file_a.rb)

    assert_equal "/root/file_a.rb", r("file_a")
    assert_equal nil,               r("file_a")
  end

  def test_require_rb_from_load_path
    set_load_path %w(/root)
    set_files %w(/root/file_a.rb)

    assert_equal "/root/file_a.rb", r("file_a.rb")
    assert_equal nil,               r("file_a.rb")
  end

  def test_require_so_file_from_load_path
    set_load_path %w(/root)
    set_files %w(/root/file_a.so)

    assert_equal "/root/file_a.so", r("file_a")
    assert_equal nil,               r("file_a")
  end

  def test_rb_takes_precendence_over_so
    set_load_path %w(/root)
    set_files %w(/root/file_a.rb /root/file_a.so)

    assert_equal "/root/file_a.rb", r("file_a")
    assert_equal nil,               r("file_a")
  end

  def test_require_from_cwd
    set_files ["#{$cwd}/file_a.rb"]

    assert_equal nil,                 r("file_a")
    assert_equal "#{$cwd}/file_a.rb", r("./file_a")
    assert_equal nil,                 r("file_a")
  end

  def test_case_insensitive_require
    set_load_path %w(/root)
    set_files %w(/root/file_a.rb /root/FILE_A.rb)

    assert_equal "/root/file_a.rb", r("file_a")
    assert_equal nil,               r("FILE_A")
  end

  def test_non_expanded_path_in_load_path
    set_load_path %w(/root/bogus/..)
    set_files %w(/root/file_a.rb)

    assert_equal "/root/file_a.rb", r("file_a")
    assert_equal nil,               r("file_a")
  end

  def test_multi_require
    set_load_path ["#{$cwd}/lib"]
    set_files ["#{$cwd}/lib/file_a.rb"]

    assert_equal "#{$cwd}/lib/file_a.rb", r("file_a")
    assert_equal nil,                    r("./lib/file_a")
  end
end
