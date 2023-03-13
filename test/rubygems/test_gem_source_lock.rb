# frozen_string_literal: true
require_relative "helper"

class TestGemSourceLock < Gem::TestCase
  def test_fetch_spec
    spec_fetcher do |fetcher|
      fetcher.spec "a", 1
    end

    name_tuple = Gem::NameTuple.new "a", v(1), "ruby"

    remote = Gem::Source.new @gem_repo
    lock   = Gem::Source::Lock.new remote

    spec = lock.fetch_spec name_tuple

    assert_equal "a-1", spec.full_name
  end

  def test_equals2
    git    = Gem::Source::Git.new "a", "git/a", nil, false
    g_lock = Gem::Source::Lock.new git

    installed = Gem::Source::Installed.new
    i_lock    = Gem::Source::Lock.new installed

    assert_equal g_lock, g_lock
    refute_equal g_lock, i_lock
    refute_equal g_lock, Object.new
  end

  def test_spaceship
    git    = Gem::Source::Git.new "a", "git/a", nil, false
    g_lock = Gem::Source::Lock.new git

    installed = Gem::Source::Installed.new
    i_lock    = Gem::Source::Lock.new installed

    vendor = Gem::Source::Vendor.new "vendor/a"
    v_lock = Gem::Source::Lock.new vendor

    assert_equal(0, g_lock.<=>(g_lock), "g_lock <=> g_lock")
    assert_equal(0, i_lock.<=>(i_lock), "i_lock <=> i_lock")
    assert_equal(0, v_lock.<=>(v_lock), "v_lock <=> v_lock")

    assert_equal(1, g_lock.<=>(i_lock), "g_lock <=> i_lock")
    assert_equal(-1, i_lock.<=>(g_lock), "i_lock <=> g_lock")

    assert_equal(-1, g_lock.<=>(v_lock), "g_lock <=> v_lock")
    assert_equal(1, v_lock.<=>(g_lock), "v_lock <=> g_lock")

    assert_equal(-1, i_lock.<=>(v_lock), "i_lock <=> v_lock")
    assert_equal(1, v_lock.<=>(i_lock), "i_lock <=> v_lock")
  end

  def test_spaceship_git
    git  = Gem::Source::Git.new "a", "git/a", nil, false
    lock = Gem::Source::Lock.new git

    assert_equal(1, lock.<=>(git),  "lock <=> git")
    assert_equal(-1, git.<=>(lock), "git <=> lock")
  end

  def test_spaceship_installed
    installed = Gem::Source::Installed.new
    lock      = Gem::Source::Lock.new installed

    assert_equal(1, lock.<=>(installed), "lock <=> installed")
    assert_equal(-1, installed.<=>(lock), "installed <=> lock")
  end

  def test_spaceship_local
    local = Gem::Source::Local.new
    lock  = Gem::Source::Lock.new local # nonsense

    assert_equal(1, lock.<=>(local), "lock <=> local")
    assert_equal(-1, local.<=>(lock), "local <=> lock")
  end

  def test_spaceship_remote
    remote = Gem::Source.new @gem_repo
    lock   = Gem::Source::Lock.new remote

    assert_equal(1, lock.<=>(remote), "lock <=> remote")
    assert_equal(-1, remote.<=>(lock), "remote <=> lock")
  end

  def test_spaceship_specific_file
    _, gem = util_gem "a", 1

    specific = Gem::Source::SpecificFile.new gem
    lock     = Gem::Source::Lock.new specific # nonsense

    assert_equal(1, lock.<=>(specific), "lock <=> specific")
    assert_equal(-1, specific.<=>(lock),      "specific <=> lock")
  end

  def test_spaceship_vendor
    vendor = Gem::Source::Vendor.new "vendor/a"
    lock   = Gem::Source::Lock.new vendor

    assert_equal(1, lock.<=>(vendor), "lock <=> vendor")
    assert_equal(-1, vendor.<=>(lock), "vendor <=> lock")
  end

  def test_uri
    remote = Gem::Source.new @gem_repo
    lock   = Gem::Source::Lock.new remote

    assert_equal URI(@gem_repo), lock.uri
  end
end
