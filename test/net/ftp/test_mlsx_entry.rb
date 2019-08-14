# frozen_string_literal: true

require "net/ftp"
require "test/unit"
require "ostruct"
require "stringio"

class MLSxEntryTest < Test::Unit::TestCase
  def test_file?
    assert_equal(true, Net::FTP::MLSxEntry.new({"type"=>"file"}, "foo").file?)
    assert_equal(false, Net::FTP::MLSxEntry.new({"type"=>"dir"}, "foo").file?)
    assert_equal(false, Net::FTP::MLSxEntry.new({"type"=>"cdir"}, "foo").file?)
    assert_equal(false, Net::FTP::MLSxEntry.new({"type"=>"pdir"}, "foo").file?)
  end

  def test_directory?
    assert_equal(false,
                 Net::FTP::MLSxEntry.new({"type"=>"file"}, "foo").directory?)
    assert_equal(true,
                 Net::FTP::MLSxEntry.new({"type"=>"dir"}, "foo").directory?)
    assert_equal(true,
                 Net::FTP::MLSxEntry.new({"type"=>"cdir"}, "foo").directory?)
    assert_equal(true,
                 Net::FTP::MLSxEntry.new({"type"=>"pdir"}, "foo").directory?)
  end

  def test_appendable?
    assert_equal(true,
                 Net::FTP::MLSxEntry.new({"perm"=>"a"}, "foo").appendable?)
    assert_equal(false,
                 Net::FTP::MLSxEntry.new({"perm"=>""}, "foo").appendable?)
  end

  def test_creatable?
    assert_equal(true,
                 Net::FTP::MLSxEntry.new({"perm"=>"c"}, "foo").creatable?)
    assert_equal(false,
                 Net::FTP::MLSxEntry.new({"perm"=>""}, "foo").creatable?)
  end

  def test_deletable?
    assert_equal(true,
                 Net::FTP::MLSxEntry.new({"perm"=>"d"}, "foo").deletable?)
    assert_equal(false,
                 Net::FTP::MLSxEntry.new({"perm"=>""}, "foo").deletable?)
  end

  def test_enterable?
    assert_equal(true,
                 Net::FTP::MLSxEntry.new({"perm"=>"e"}, "foo").enterable?)
    assert_equal(false,
                 Net::FTP::MLSxEntry.new({"perm"=>""}, "foo").enterable?)
  end

  def test_renamable?
    assert_equal(true,
                 Net::FTP::MLSxEntry.new({"perm"=>"f"}, "foo").renamable?)
    assert_equal(false,
                 Net::FTP::MLSxEntry.new({"perm"=>""}, "foo").renamable?)
  end

  def test_listable?
    assert_equal(true,
                 Net::FTP::MLSxEntry.new({"perm"=>"l"}, "foo").listable?)
    assert_equal(false,
                 Net::FTP::MLSxEntry.new({"perm"=>""}, "foo").listable?)
  end

  def test_directory_makable?
    assert_equal(true,
                 Net::FTP::MLSxEntry.new({"perm"=>"m"}, "foo").
                 directory_makable?)
    assert_equal(false,
                 Net::FTP::MLSxEntry.new({"perm"=>""}, "foo").
                 directory_makable?)
  end

  def test_purgeable?
    assert_equal(true,
                 Net::FTP::MLSxEntry.new({"perm"=>"p"}, "foo").purgeable?)
    assert_equal(false,
                 Net::FTP::MLSxEntry.new({"perm"=>""}, "foo").purgeable?)
  end

  def test_readable?
    assert_equal(true,
                 Net::FTP::MLSxEntry.new({"perm"=>"r"}, "foo").readable?)
    assert_equal(false,
                 Net::FTP::MLSxEntry.new({"perm"=>""}, "foo").readable?)
  end

  def test_writable?
    assert_equal(true,
                 Net::FTP::MLSxEntry.new({"perm"=>"w"}, "foo").writable?)
    assert_equal(false,
                 Net::FTP::MLSxEntry.new({"perm"=>""}, "foo").writable?)
  end
end
