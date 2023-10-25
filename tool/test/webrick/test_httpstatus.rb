# frozen_string_literal: false
require "test/unit"
require "webrick"

class TestWEBrickHTTPStatus < Test::Unit::TestCase
  def test_info?
    assert WEBrick::HTTPStatus.info?(100)
    refute WEBrick::HTTPStatus.info?(200)
  end

  def test_success?
    assert WEBrick::HTTPStatus.success?(200)
    refute WEBrick::HTTPStatus.success?(300)
  end

  def test_redirect?
    assert WEBrick::HTTPStatus.redirect?(300)
    refute WEBrick::HTTPStatus.redirect?(400)
  end

  def test_error?
    assert WEBrick::HTTPStatus.error?(400)
    refute WEBrick::HTTPStatus.error?(600)
  end

  def test_client_error?
    assert WEBrick::HTTPStatus.client_error?(400)
    refute WEBrick::HTTPStatus.client_error?(500)
  end

  def test_server_error?
    assert WEBrick::HTTPStatus.server_error?(500)
    refute WEBrick::HTTPStatus.server_error?(600)
  end
end
