# frozen_string_literal: true
require 'rubygems/test_case'
require "rubygems/version"

class TestGemVersion < Gem::TestCase

  class V < ::Gem::Version
  end

  def test_bump
    assert_bumped_version_equal "5.3", "5.2.4"
  end

  def test_bump_alpha
    assert_bumped_version_equal "5.3", "5.2.4.a"
  end

  def test_bump_alphanumeric
    assert_bumped_version_equal "5.3", "5.2.4.a10"
  end

  def test_bump_trailing_zeros
    assert_bumped_version_equal "5.1", "5.0.0"
  end

  def test_bump_one_level
    assert_bumped_version_equal "6", "5"
  end

  # A Gem::Version is already a Gem::Version and therefore not transformed by
  # Gem::Version.create

  def test_class_create
    real = Gem::Version.new(1.0)

    assert_same  real, Gem::Version.create(real)
    assert_nil   Gem::Version.create(nil)
    assert_equal v("5.1"), Gem::Version.create("5.1")

    ver = '1.1'.freeze
    assert_equal v('1.1'), Gem::Version.create(ver)
  end

  def test_class_correct
    assert_equal true,  Gem::Version.correct?("5.1")
    assert_equal false, Gem::Version.correct?("an incorrect version")
  end

  def test_class_new_subclass
    v1 = Gem::Version.new '1'
    v2 = V.new '1'

    refute_same v1, v2
  end

  def test_eql_eh
    assert_version_eql "1.2",    "1.2"
    refute_version_eql "1.2",    "1.2.0"
    refute_version_eql "1.2",    "1.3"
    refute_version_eql "1.2.b1", "1.2.b.1"
  end

  def test_equals2
    assert_version_equal "1.2",    "1.2"
    refute_version_equal "1.2",    "1.3"
    assert_version_equal "1.2.b1", "1.2.b.1"
  end

  # REVISIT: consider removing as too impl-bound
  def test_hash
    assert_equal v("1.2").hash, v("1.2").hash
    refute_equal v("1.2").hash, v("1.3").hash
    assert_equal v("1.2").hash, v("1.2.0").hash
    assert_equal v("1.2.pre.1").hash, v("1.2.0.pre.1.0").hash
  end

  def test_initialize
    ["1.0", "1.0 ", " 1.0 ", "1.0\n", "\n1.0\n", "1.0".freeze].each do |good|
      assert_version_equal "1.0", good
    end

    assert_version_equal "1", 1
  end

  def test_initialize_invalid
    invalid_versions = %W[
      junk
      1.0\n2.0
      1..2
      1.2\ 3.4
    ]

    # DON'T TOUCH THIS WITHOUT CHECKING CVE-2013-4287
    invalid_versions << "2.3422222.222.222222222.22222.ads0as.dasd0.ddd2222.2.qd3e."

    invalid_versions.each do |invalid|
      e = assert_raises ArgumentError, invalid do
        Gem::Version.new invalid
      end

      assert_equal "Malformed version number string #{invalid}", e.message, invalid
    end
  end

  def test_empty_version
    ["", "   ", " "].each do |empty|
      assert_equal "0", Gem::Version.new(empty).version
    end
  end

  def test_prerelease
    assert_prerelease "1.2.0.a"
    assert_prerelease "2.9.b"
    assert_prerelease "22.1.50.0.d"
    assert_prerelease "1.2.d.42"

    assert_prerelease '1.A'

    assert_prerelease '1-1'
    assert_prerelease '1-a'

    refute_prerelease "1.2.0"
    refute_prerelease "2.9"
    refute_prerelease "22.1.50.0"
  end

  def test_release
    assert_release_equal "1.2.0", "1.2.0.a"
    assert_release_equal "1.1",   "1.1.rc10"
    assert_release_equal "1.9.3", "1.9.3.alpha.5"
    assert_release_equal "1.9.3", "1.9.3"
  end

  def test_spaceship
    assert_equal( 0, v("1.0")       <=> v("1.0.0"))
    assert_equal( 1, v("1.0")       <=> v("1.0.a"))
    assert_equal( 1, v("1.8.2")     <=> v("0.0.0"))
    assert_equal( 1, v("1.8.2")     <=> v("1.8.2.a"))
    assert_equal( 1, v("1.8.2.b")   <=> v("1.8.2.a"))
    assert_equal(-1, v("1.8.2.a")   <=> v("1.8.2"))
    assert_equal( 1, v("1.8.2.a10") <=> v("1.8.2.a9"))
    assert_equal( 0, v("")          <=> v("0"))

    assert_nil v("1.0") <=> "whatever"
  end

  def test_approximate_recommendation
    assert_approximate_equal "~> 1.0", "1"
    assert_approximate_equal "~> 1.0", "1.0"
    assert_approximate_equal "~> 1.2", "1.2"
    assert_approximate_equal "~> 1.2", "1.2.0"
    assert_approximate_equal "~> 1.2", "1.2.3"
    assert_approximate_equal "~> 1.2", "1.2.3.a.4"
  end

  def test_to_s
    assert_equal "5.2.4", v("5.2.4").to_s
  end

  def test_semver
    assert_less_than "1.0.0-alpha", "1.0.0-alpha.1"
    assert_less_than "1.0.0-alpha.1", "1.0.0-beta.2"
    assert_less_than "1.0.0-beta.2", "1.0.0-beta.11"
    assert_less_than "1.0.0-beta.11", "1.0.0-rc.1"
    assert_less_than "1.0.0-rc1", "1.0.0"
    assert_less_than "1.0.0-1", "1"
  end

  # modifying the segments of a version should not affect the segments of the cached version object
  def test_segments
    v('9.8.7').segments[2] += 1

    refute_version_equal "9.8.8", "9.8.7"
    assert_equal         [9,8,7], v("9.8.7").segments
  end

  def test_canonical_segments
    assert_equal [1], v("1.0.0").canonical_segments
    assert_equal [1, "a", 1], v("1.0.0.a.1.0").canonical_segments
    assert_equal [1, 2, 3, "pre", 1], v("1.2.3-1").canonical_segments
  end

  # Asserts that +version+ is a prerelease.

  def assert_prerelease version
    assert v(version).prerelease?, "#{version} is a prerelease"
  end

  # Assert that +expected+ is the "approximate" recommendation for +version".

  def assert_approximate_equal expected, version
    assert_equal expected, v(version).approximate_recommendation
  end

  # Assert that bumping the +unbumped+ version yields the +expected+.

  def assert_bumped_version_equal expected, unbumped
    assert_version_equal expected, v(unbumped).bump
  end

  # Assert that +release+ is the correct non-prerelease +version+.

  def assert_release_equal release, version
    assert_version_equal release, v(version).release
  end

  # Assert that two versions are equal. Handles strings or
  # Gem::Version instances.

  def assert_version_equal expected, actual
    assert_equal v(expected), v(actual)
    assert_equal v(expected).hash, v(actual).hash, "since #{actual} == #{expected}, they must have the same hash"
  end

  # Assert that two versions are eql?. Checks both directions.

  def assert_version_eql first, second
    first, second = v(first), v(second)
    assert first.eql?(second), "#{first} is eql? #{second}"
    assert second.eql?(first), "#{second} is eql? #{first}"
  end

  def assert_less_than left, right
    l = v(left)
    r = v(right)
    assert l < r, "#{left} not less than #{right}"
  end

  # Refute the assumption that +version+ is a prerelease.

  def refute_prerelease version
    refute v(version).prerelease?, "#{version} is NOT a prerelease"
  end

  # Refute the assumption that two versions are eql?. Checks both
  # directions.

  def refute_version_eql first, second
    first, second = v(first), v(second)
    refute first.eql?(second), "#{first} is NOT eql? #{second}"
    refute second.eql?(first), "#{second} is NOT eql? #{first}"
  end

  # Refute the assumption that the two versions are equal?.

  def refute_version_equal unexpected, actual
    refute_equal v(unexpected), v(actual)
  end
end
