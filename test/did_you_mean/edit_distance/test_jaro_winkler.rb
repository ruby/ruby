require_relative '../helper'

# These tests were originally written by Jian Weihang (簡煒航) as part of his work
# on the jaro_winkler gem. The original code could be found here:
#   https://github.com/tonytonyjan/jaro_winkler/blob/9bd12421/spec/jaro_winkler_spec.rb
#
# Copyright (c) 2014 Jian Weihang

class JaroWinklerTest < Test::Unit::TestCase
  def test_jaro_winkler_distance
    assert_distance 0.9667, 'henka',      'henkan'
    assert_distance 1.0,    'al',         'al'
    assert_distance 0.9611, 'martha',     'marhta'
    assert_distance 0.8324, 'jones',      'johnson'
    assert_distance 0.9167, 'abcvwxyz',   'zabcvwxy'
    assert_distance 0.9583, 'abcvwxyz',   'cabvwxyz'
    assert_distance 0.84,   'dwayne',     'duane'
    assert_distance 0.8133, 'dixon',      'dicksonx'
    assert_distance 0.0,    'fvie',       'ten'
    assert_distance 0.9067, 'does_exist', 'doesnt_exist'
    assert_distance 1.0, 'x', 'x'
  end

  def test_jarowinkler_distance_with_utf8_strings
    assert_distance 0.9818, '變形金剛4:絕跡重生', '變形金剛4: 絕跡重生'
    assert_distance 0.8222, '連勝文',             '連勝丼'
    assert_distance 0.8222, '馬英九',             '馬英丸'
    assert_distance 0.6667, '良い',               'いい'
  end

  private

  def assert_distance(score, str1, str2)
    assert_equal score, DidYouMean::JaroWinkler.distance(str1, str2).round(4)
  end
end
