# frozen_string_literal: false
require 'test/unit'
require 'cgi'
require 'cgi/session'
require 'cgi/session/pstore'
require 'stringio'
require 'tmpdir'
require_relative 'update_env'

class CGISessionTest < Test::Unit::TestCase
  include UpdateEnv

  def setup
    @environ = {}
    @session_dir = Dir.mktmpdir(%w'session dir')
  end

  def teardown
    ENV.update(@environ)
    $stdout = STDOUT
    FileUtils.rm_rf(@session_dir)
  end

  def test_cgi_session_filestore
    update_env(
      'REQUEST_METHOD'  => 'GET',
  #    'QUERY_STRING'    => 'id=123&id=456&id=&str=%40h+%3D%7E+%2F%5E%24%2F',
  #    'HTTP_COOKIE'     => '_session_id=12345; name1=val1&val2;',
      'SERVER_SOFTWARE' => 'Apache 2.2.0',
      'SERVER_PROTOCOL' => 'HTTP/1.1',
    )
    value1="value1"
    value2="\x8F\xBC\x8D]"
    value2.force_encoding("SJIS") if defined?(::Encoding)
    cgi = CGI.new
    session = CGI::Session.new(cgi,"tmpdir"=>@session_dir)
    session["key1"]=value1
    session["key2"]=value2
    assert_equal(value1,session["key1"])
    assert_equal(value2,session["key2"])
    session.close
    $stdout = StringIO.new
    cgi.out{""}

    update_env(
      'REQUEST_METHOD'  => 'GET',
      # 'HTTP_COOKIE'     => "_session_id=#{session_id}",
      'QUERY_STRING'    => "_session_id=#{session.session_id}",
      'SERVER_SOFTWARE' => 'Apache 2.2.0',
      'SERVER_PROTOCOL' => 'HTTP/1.1',
    )
    cgi = CGI.new
    session = CGI::Session.new(cgi,"tmpdir"=>@session_dir)
    $stdout = StringIO.new
    assert_equal(value1,session["key1"])
    assert_equal(value2,session["key2"])
    session.close

  end
  def test_cgi_session_pstore
    update_env(
      'REQUEST_METHOD'  => 'GET',
  #    'QUERY_STRING'    => 'id=123&id=456&id=&str=%40h+%3D%7E+%2F%5E%24%2F',
  #    'HTTP_COOKIE'     => '_session_id=12345; name1=val1&val2;',
      'SERVER_SOFTWARE' => 'Apache 2.2.0',
      'SERVER_PROTOCOL' => 'HTTP/1.1',
    )
    value1="value1"
    value2="\x8F\xBC\x8D]"
    value2.force_encoding("SJIS") if defined?(::Encoding)
    cgi = CGI.new
    session = CGI::Session.new(cgi,"tmpdir"=>@session_dir,"database_manager"=>CGI::Session::PStore)
    session["key1"]=value1
    session["key2"]=value2
    assert_equal(value1,session["key1"])
    assert_equal(value2,session["key2"])
    session.close
    $stdout = StringIO.new
    cgi.out{""}

    update_env(
      'REQUEST_METHOD'  => 'GET',
      # 'HTTP_COOKIE'     => "_session_id=#{session_id}",
      'QUERY_STRING'    => "_session_id=#{session.session_id}",
      'SERVER_SOFTWARE' => 'Apache 2.2.0',
      'SERVER_PROTOCOL' => 'HTTP/1.1',
    )
    cgi = CGI.new
    session = CGI::Session.new(cgi,"tmpdir"=>@session_dir,"database_manager"=>CGI::Session::PStore)
    $stdout = StringIO.new
    assert_equal(value1,session["key1"])
    assert_equal(value2,session["key2"])
    session.close
  end
  def test_cgi_session_specify_session_id
    update_env(
      'REQUEST_METHOD'  => 'GET',
  #    'QUERY_STRING'    => 'id=123&id=456&id=&str=%40h+%3D%7E+%2F%5E%24%2F',
  #    'HTTP_COOKIE'     => '_session_id=12345; name1=val1&val2;',
      'SERVER_SOFTWARE' => 'Apache 2.2.0',
      'SERVER_PROTOCOL' => 'HTTP/1.1',
    )
    value1="value1"
    value2="\x8F\xBC\x8D]"
    value2.force_encoding("SJIS") if defined?(::Encoding)
    cgi = CGI.new
    session = CGI::Session.new(cgi,"tmpdir"=>@session_dir,"session_id"=>"foo")
    session["key1"]=value1
    session["key2"]=value2
    assert_equal(value1,session["key1"])
    assert_equal(value2,session["key2"])
    assert_equal("foo",session.session_id)
    #session_id=session.session_id
    session.close
    $stdout = StringIO.new
    cgi.out{""}

    update_env(
      'REQUEST_METHOD'  => 'GET',
      # 'HTTP_COOKIE'     => "_session_id=#{session_id}",
      'QUERY_STRING'    => "_session_id=#{session.session_id}",
      'SERVER_SOFTWARE' => 'Apache 2.2.0',
      'SERVER_PROTOCOL' => 'HTTP/1.1',
    )
    cgi = CGI.new
    session = CGI::Session.new(cgi,"tmpdir"=>@session_dir)
    $stdout = StringIO.new
    assert_equal(value1,session["key1"])
    assert_equal(value2,session["key2"])
    assert_equal("foo",session.session_id)
    session.close
  end
  def test_cgi_session_specify_session_key
    update_env(
      'REQUEST_METHOD'  => 'GET',
  #    'QUERY_STRING'    => 'id=123&id=456&id=&str=%40h+%3D%7E+%2F%5E%24%2F',
  #    'HTTP_COOKIE'     => '_session_id=12345; name1=val1&val2;',
      'SERVER_SOFTWARE' => 'Apache 2.2.0',
      'SERVER_PROTOCOL' => 'HTTP/1.1',
    )
    value1="value1"
    value2="\x8F\xBC\x8D]"
    value2.force_encoding("SJIS") if defined?(::Encoding)
    cgi = CGI.new
    session = CGI::Session.new(cgi,"tmpdir"=>@session_dir,"session_key"=>"bar")
    session["key1"]=value1
    session["key2"]=value2
    assert_equal(value1,session["key1"])
    assert_equal(value2,session["key2"])
    session_id=session.session_id
    session.close
    $stdout = StringIO.new
    cgi.out{""}

    update_env(
      'REQUEST_METHOD'  => 'GET',
      'HTTP_COOKIE'     => "bar=#{session_id}",
      # 'QUERY_STRING'    => "bar=#{session.session_id}",
      'SERVER_SOFTWARE' => 'Apache 2.2.0',
      'SERVER_PROTOCOL' => 'HTTP/1.1',
    )
    cgi = CGI.new
    session = CGI::Session.new(cgi,"tmpdir"=>@session_dir,"session_key"=>"bar")
    $stdout = StringIO.new
    assert_equal(value1,session["key1"])
    assert_equal(value2,session["key2"])
    session.close
  end
end
