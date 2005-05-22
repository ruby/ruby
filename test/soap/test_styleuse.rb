require 'test/unit'
require 'soap/rpc/httpserver'
require 'soap/rpc/driver'


module SOAP


class TestStyleUse < Test::Unit::TestCase
  # rpc driver: obj in(Hash allowed for literal), obj out
  # 
  #   style: not visible from user
  #     rpc: wrapped element
  #     document: unwrappted element
  #
  #   use:
  #     encoding: a graph (SOAP Data Model)
  #     literal: not a graph (SOAPElement)
  #
  # rpc stub: obj in, obj out(Hash is allowed for literal)
  #
  #   style: not visible from user
  #     rpc: wrapped element
  #     document: unwrappted element
  #
  #   use:
  #     encoding: a graph (SOAP Data Model)
  #     literal: not a graph (SOAPElement)
  #
  # document driver: SOAPElement in, SOAPElement out? [not implemented]
  #
  #   style: ditto
  #   use: ditto
  #
  #
  # document stub: SOAPElement in, SOAPElement out? [not implemented]
  #
  #   style: ditto
  #   use: ditto
  #
  class GenericServant
    # method name style: requeststyle_requestuse_responsestyle_responseuse

    # 2 params -> array
    def rpc_enc_rpc_enc(obj1, obj2)
      [obj1, [obj1, obj2]]
    end

    # 2 objs -> array
    def rpc_lit_rpc_enc(obj1, obj2)
      [obj2, obj1]
    end

    # 2 params -> 2 params
    def rpc_enc_rpc_lit(obj1, obj2)
      klass = [obj1.class.name, obj2.class.name]
      [obj2, obj1]
    end

    # 2 objs -> 2 objs
    def rpc_lit_rpc_lit(obj1, obj2)
      [obj1, obj2]
    end

    # 2 params -> array
    def doc_enc_doc_enc(obj1, obj2)
      [obj1, [obj1, obj2]]
    end

    # 2 objs -> array
    def doc_lit_doc_enc(obj1, obj2)
      [obj2, obj1]
    end

    # 2 params -> 2 hashes
    def doc_enc_doc_lit(obj1, obj2)
      klass = [obj1.class.name, obj2.class.name]
      return {'obj1' => {'klass' => klass}, 'misc' => 'hash does not have an order'},
        {'obj2' => {'klass' => klass}}
    end

    # 2 objs -> 2 objs
    def doc_lit_doc_lit(obj1, obj2)
      return obj1, obj2
    end
  end

  Namespace = "urn:styleuse"

  module Op
    def self.opt(request_style, request_use, response_style, response_use)
      {
        :request_style => request_style,
        :request_use => request_use,
        :response_style => response_style,
        :response_use => response_use
      }
    end

    Op_rpc_enc_rpc_enc = [
      XSD::QName.new(Namespace, 'rpc_enc_rpc_enc'),
      nil,
      'rpc_enc_rpc_enc', [
        ['in', 'obj1', nil],
        ['in', 'obj2', nil],
        ['retval', 'return', nil]],
      opt(:rpc, :encoded, :rpc, :encoded)
    ]

    Op_rpc_lit_rpc_enc = [
      XSD::QName.new(Namespace, 'rpc_lit_rpc_enc'),
      nil,
      'rpc_lit_rpc_enc', [
        ['in', 'obj1', nil],
        ['in', 'obj2', nil],
        ['retval', 'return', nil]],
      opt(:rpc, :literal, :rpc, :encoded)
    ]

    Op_rpc_enc_rpc_lit = [
      XSD::QName.new(Namespace, 'rpc_enc_rpc_lit'),
      nil,
      'rpc_enc_rpc_lit', [
        ['in', 'obj1', nil],
        ['in', 'obj2', nil],
        ['retval', 'ret1', nil],
        ['out', 'ret2', nil]],
      opt(:rpc, :encoded, :rpc, :literal)
    ]

    Op_rpc_lit_rpc_lit = [
      XSD::QName.new(Namespace, 'rpc_lit_rpc_lit'),
      nil,
      'rpc_lit_rpc_lit', [
        ['in', 'obj1', nil],
        ['in', 'obj2', nil],
        ['retval', 'ret1', nil],
        ['out', 'ret2', nil]],
      opt(:rpc, :literal, :rpc, :literal)
    ]

    Op_doc_enc_doc_enc = [
      Namespace + 'doc_enc_doc_enc',
      'doc_enc_doc_enc', [
        ['in', 'obj1', [nil, Namespace, 'obj1']],
        ['in', 'obj2', [nil, Namespace, 'obj2']],
        ['out', 'ret1', [nil, Namespace, 'ret1']],
        ['out', 'ret2', [nil, Namespace, 'ret2']]],
      opt(:document, :encoded, :document, :encoded)
    ]

    Op_doc_lit_doc_enc = [
      Namespace + 'doc_lit_doc_enc',
      'doc_lit_doc_enc', [
        ['in', 'obj1', [nil, Namespace, 'obj1']],
        ['in', 'obj2', [nil, Namespace, 'obj2']],
        ['out', 'ret1', [nil, Namespace, 'ret1']],
        ['out', 'ret2', [nil, Namespace, 'ret2']]],
      opt(:document, :literal, :document, :encoded)
    ]

    Op_doc_enc_doc_lit = [
      Namespace + 'doc_enc_doc_lit',
      'doc_enc_doc_lit', [
        ['in', 'obj1', [nil, Namespace, 'obj1']],
        ['in', 'obj2', [nil, Namespace, 'obj2']],
        ['out', 'ret1', [nil, Namespace, 'ret1']],
        ['out', 'ret2', [nil, Namespace, 'ret2']]],
      opt(:document, :encoded, :document, :literal)
    ]

    Op_doc_lit_doc_lit = [
      Namespace + 'doc_lit_doc_lit',
      'doc_lit_doc_lit', [
        ['in', 'obj1', [nil, Namespace, 'obj1']],
        ['in', 'obj2', [nil, Namespace, 'obj2']],
        ['out', 'ret1', [nil, Namespace, 'ret1']],
        ['out', 'ret2', [nil, Namespace, 'ret2']]],
      opt(:document, :literal, :document, :literal)
    ]
  end

  include Op

  class Server < ::SOAP::RPC::HTTPServer
    include Op

    def on_init
      @servant = GenericServant.new
      add_rpc_operation(@servant, *Op_rpc_enc_rpc_enc)
      add_rpc_operation(@servant, *Op_rpc_lit_rpc_enc)
      add_rpc_operation(@servant, *Op_rpc_enc_rpc_lit)
      add_rpc_operation(@servant, *Op_rpc_lit_rpc_lit)
      add_document_operation(@servant, *Op_doc_enc_doc_enc)
      add_document_operation(@servant, *Op_doc_lit_doc_enc)
      add_document_operation(@servant, *Op_doc_enc_doc_lit)
      add_document_operation(@servant, *Op_doc_lit_doc_lit)
    end
  end

  Port = 17171

  def setup
    setup_server
    setup_client
  end

  def setup_server
    @server = Server.new(
      :BindAddress => "0.0.0.0",
      :Port => Port,
      :AccessLog => [],
      :SOAPDefaultNamespace => Namespace
    )
    @server.level = Logger::Severity::ERROR
    @server_thread = start_server_thread(@server)
  end

  def setup_client
    @client = ::SOAP::RPC::Driver.new("http://localhost:#{Port}/", Namespace)
    @client.wiredump_dev = STDERR if $DEBUG
    @client.add_rpc_operation(*Op_rpc_enc_rpc_enc)
    @client.add_rpc_operation(*Op_rpc_lit_rpc_enc)
    @client.add_rpc_operation(*Op_rpc_enc_rpc_lit)
    @client.add_rpc_operation(*Op_rpc_lit_rpc_lit)
    @client.add_document_operation(*Op_doc_enc_doc_enc)
    @client.add_document_operation(*Op_doc_lit_doc_enc)
    @client.add_document_operation(*Op_doc_enc_doc_lit)
    @client.add_document_operation(*Op_doc_lit_doc_lit)
  end

  def teardown
    teardown_server
    teardown_client
  end

  def teardown_server
    @server.shutdown
    @server_thread.kill
    @server_thread.join
  end

  def teardown_client
    @client.reset_stream
  end

  def start_server_thread(server)
    t = Thread.new {
      Thread.current.abort_on_exception = true
      server.start
    }
    t
  end

  def test_rpc_enc_rpc_enc
    o = "hello"
    obj1 = o
    obj2 = [1]
    ret = @client.rpc_enc_rpc_enc(obj1, obj2)
    # server returns [obj1, [obj1, obj2]]
    assert_equal([obj1, [obj1, obj2]], ret)
    assert_same(ret[0], ret[1][0])
  end

  S1 = ::Struct.new(:a)
  S2 = ::Struct.new(:c)
  def test_rpc_lit_rpc_enc
    ret1, ret2 = @client.rpc_lit_rpc_enc(S1.new('b'), S2.new('d'))
    assert_equal('d', ret1.c)
    assert_equal('b', ret2.a)
    # Hash is allowed for literal
    ret1, ret2 = @client.rpc_lit_rpc_enc({'a' => 'b'}, {'c' => 'd'})
    assert_equal('d', ret1.c)
    assert_equal('b', ret2.a)
    # simple value
    assert_equal(
      ['1', 'a'],
      @client.rpc_lit_rpc_enc('a', 1)
    )
  end

  def test_rpc_enc_rpc_lit
    assert_equal(
      ['1', 'a'],
      @client.rpc_enc_rpc_lit('a', '1')
    )
  end

  def test_rpc_lit_rpc_lit
    ret1, ret2 = @client.rpc_lit_rpc_lit({'a' => 'b'}, {'c' => 'd'})
    assert_equal('b', ret1["a"])
    assert_equal('d', ret2["c"])
  end

  def test_doc_enc_doc_enc
    o = "hello"
    obj1 = o
    obj2 = [1]
    ret = @client.rpc_enc_rpc_enc(obj1, obj2)
    # server returns [obj1, [obj1, obj2]]
    assert_equal([obj1, [obj1, obj2]], ret)
    assert_same(ret[0], ret[1][0])
  end

  def test_doc_lit_doc_enc
    ret1, ret2 = @client.doc_lit_doc_enc({'a' => 'b'}, {'c' => 'd'})
    assert_equal('d', ret1.c)
    assert_equal('b', ret2.a)
    assert_equal(
      ['a', '1'],
      @client.doc_lit_doc_enc(1, 'a')
    )
  end

  def test_doc_enc_doc_lit
    ret1, ret2 = @client.doc_enc_doc_lit('a', 1)
    # literal Array
    assert_equal(['String', 'Fixnum'], ret1['obj1']['klass'])
    # same value
    assert_equal(ret1['obj1']['klass'], ret2['obj2']['klass'])
    # not the same object (not encoded)
    assert_not_same(ret1['obj1']['klass'], ret2['obj2']['klass'])
  end

  def test_doc_lit_doc_lit
    ret1, ret2 = @client.doc_lit_doc_lit({'a' => 'b'}, {'c' => 'd'})
    assert_equal('b', ret1["a"])
    assert_equal('d', ret2["c"])
  end
end


end
