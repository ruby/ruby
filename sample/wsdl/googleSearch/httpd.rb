#!/usr/bin/env ruby

require 'webrick'
require 'getopts'

getopts "", 'r:', 'p:8808'

s = WEBrick::HTTPServer.new(
  :BindAddress => "0.0.0.0",
  :Port => $OPT_p.to_i,
  :DocumentRoot => $OPT_r || ".",
  :CGIPathEnv => ENV['PATH']
)
trap(:INT){ s.shutdown }
s.start
