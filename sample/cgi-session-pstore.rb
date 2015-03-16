require 'cgi'
require 'cgi/session/pstore'

STDIN.reopen(IO::NULL)
cgi = CGI.new
session = CGI::Session.new(cgi, 'database_manager' => CGI::Session::PStore)
session['key'] = {'k' => 'v'}
puts session['key'].class
fail unless Hash === session['key']
puts session['key'].inspect
fail unless session['key'].inspect == '{"k"=>"v"}'
