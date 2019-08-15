# frozen_string_literal: false
require 'test/unit'
require 'uri/file'

class URI::TestFile < Test::Unit::TestCase
  def test_parse
    u = URI("file://example.com/file")
    assert_equal "/file", u.path

    u = URI("file://localhost/file")
    assert_equal "/file", u.path
    assert_equal "file:///file", u.to_s

    u = URI("file://localhost:30/file")
    assert_equal "", u.host
    assert_equal nil, u.port
    assert_equal "/file", u.path
    assert_equal "file:///file", u.to_s

    u = URI("file:///file")
    assert_equal "/file", u.path
    assert_equal "file:///file", u.to_s

    u = URI("file:/file")
    assert_equal "/file", u.path
    assert_equal "file:///file", u.to_s

    u = URI("file://foo:pass@example.com/file")
    assert_equal "/file", u.path
    assert_equal nil, u.user
    assert_equal nil, u.password

    u = URI("file:///c:/path/to/file")
    assert_equal "/c:/path/to/file", u.path

    # this form is not supported
    u = URI("file:c:/path/to/file")
    assert_equal "c:/path/to/file", u.opaque

  end

  def test_build
    u = URI::File.build(scheme: "file", host: "example.com", path:"/file")
    assert_equal "/file", u.path
    assert_equal "file://example.com/file", u.to_s
    assert_raise(URI::InvalidURIError){ u.user = "foo" }
    assert_raise(URI::InvalidURIError){ u.password = "foo" }
    assert_raise(URI::InvalidURIError){ u.userinfo = "foo" }
    assert_raise(URI::InvalidURIError){ URI::File.build(scheme: "file", userinfo: "foo", host: "example.com", path:"/file") }

    u = URI::File.build(scheme: "file", path:"/file")
    assert_equal "", u.host
    assert_equal "/file", u.path
    assert_equal "file:///file", u.to_s

    u = URI::File.build(scheme: "file", host: "localhost", path:"/file")
    assert_equal "", u.host
    assert_equal "/file", u.path
    assert_equal "file:///file", u.to_s

    u = URI::File.build(scheme: "file", path:"/file", port: 30)
    assert_equal "", u.host
    assert_equal nil, u.port
    assert_equal "/file", u.path
    assert_equal "file:///file", u.to_s
  end
end
