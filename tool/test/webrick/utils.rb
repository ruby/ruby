# frozen_string_literal: false
require "webrick"
begin
  require "webrick/https"
rescue LoadError
end
require "webrick/httpproxy"

module TestWEBrick
  NullWriter = Object.new
  def NullWriter.<<(msg)
    puts msg if $DEBUG
    return self
  end

  class WEBrick::HTTPServlet::CGIHandler
    remove_const :Ruby
    require "envutil" unless defined?(EnvUtil)
    Ruby = EnvUtil.rubybin
    remove_const :CGIRunner
    CGIRunner = "\"#{Ruby}\" \"#{WEBrick::Config::LIBDIR}/httpservlet/cgi_runner.rb\"" # :nodoc:
    remove_const :CGIRunnerArray
    CGIRunnerArray = [Ruby, "#{WEBrick::Config::LIBDIR}/httpservlet/cgi_runner.rb"] # :nodoc:
  end

  RubyBin = "\"#{EnvUtil.rubybin}\""
  RubyBin << " --disable-gems"
  RubyBin << " \"-I#{File.expand_path("../..", File.dirname(__FILE__))}/lib\""
  RubyBin << " \"-I#{File.dirname(EnvUtil.rubybin)}/.ext/common\""
  RubyBin << " \"-I#{File.dirname(EnvUtil.rubybin)}/.ext/#{RUBY_PLATFORM}\""

  RubyBinArray = [EnvUtil.rubybin]
  RubyBinArray << "--disable-gems"
  RubyBinArray << "-I" << "#{File.expand_path("../..", File.dirname(__FILE__))}/lib"
  RubyBinArray << "-I" << "#{File.dirname(EnvUtil.rubybin)}/.ext/common"
  RubyBinArray << "-I" << "#{File.dirname(EnvUtil.rubybin)}/.ext/#{RUBY_PLATFORM}"

  require "test/unit" unless defined?(Test::Unit)
  include Test::Unit::Assertions
  extend Test::Unit::Assertions
  include Test::Unit::CoreAssertions
  extend Test::Unit::CoreAssertions

  module_function

  DefaultLogTester = lambda {|log, access_log| assert_equal([], log) }

  def start_server(klass, config={}, log_tester=DefaultLogTester, &block)
    log_ary = []
    access_log_ary = []
    log = proc { "webrick log start:\n" + (log_ary+access_log_ary).join.gsub(/^/, "  ").chomp + "\nwebrick log end" }
    config = ({
      :BindAddress => "127.0.0.1", :Port => 0,
      :ServerType => Thread,
      :Logger => WEBrick::Log.new(log_ary, WEBrick::BasicLog::WARN),
      :AccessLog => [[access_log_ary, ""]]
    }.update(config))
    server = capture_output {break klass.new(config)}
    server_thread = server.start
    server_thread2 = Thread.new {
      server_thread.join
      if log_tester
        log_tester.call(log_ary, access_log_ary)
      end
    }
    addr = server.listeners[0].addr
    client_thread = Thread.new {
      begin
        block.yield([server, addr[3], addr[1], log])
      ensure
        server.shutdown
      end
    }
    assert_join_threads([client_thread, server_thread2])
  end

  def start_httpserver(config={}, log_tester=DefaultLogTester, &block)
    start_server(WEBrick::HTTPServer, config, log_tester, &block)
  end

  def start_httpproxy(config={}, log_tester=DefaultLogTester, &block)
    start_server(WEBrick::HTTPProxyServer, config, log_tester, &block)
  end
end
