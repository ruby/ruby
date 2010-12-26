require 'rubygems'
require 'test/unit'
require 'tmpdir'
require 'fileutils'
require 'rdoc/ri/paths'
require_relative '../ruby/envutil'

class TestRDocRIPaths < Test::Unit::TestCase

  def setup
    RDoc::RI::Paths.instance_variable_set :@gemdirs, %w[/nonexistent/gemdir]
  end

  def teardown
    RDoc::RI::Paths.instance_variable_set :@gemdirs, nil
  end

  def test_class_path_nonexistent
    path = RDoc::RI::Paths.path true, true, true, true, '/nonexistent'

    refute_includes path, '/nonexistent'
  end

  def test_class_raw_path
    path = RDoc::RI::Paths.raw_path true, true, true, true

    assert_equal RDoc::RI::Paths::SYSDIR,  path.shift
    assert_equal RDoc::RI::Paths::SITEDIR, path.shift
    assert_equal RDoc::RI::Paths::HOMEDIR, path.shift
    assert_equal '/nonexistent/gemdir',    path.shift
  end

  def test_class_raw_path_extra_dirs
    path = RDoc::RI::Paths.raw_path true, true, true, true, '/nonexistent'

    assert_equal '/nonexistent',           path.shift
    assert_equal RDoc::RI::Paths::SYSDIR,  path.shift
    assert_equal RDoc::RI::Paths::SITEDIR, path.shift
    assert_equal RDoc::RI::Paths::HOMEDIR, path.shift
    assert_equal '/nonexistent/gemdir',    path.shift
  end

  def test_homeless
    bug4202 = '[ruby-core:33867]'
    assert(assert_in_out_err([{"HOME"=>nil}, *%w"-rrdoc/ri/paths -e;"], bug4202).success?, bug4202)
  end
end

