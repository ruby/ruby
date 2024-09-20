# frozen_string_literal: false
require 'win32ole'
db = WIN32OLE.new('ADODB.Connection')
db.connectionString = "Driver={Microsoft Text Driver (*.txt; *.csv)};DefaultDir=.;"
ev = WIN32OLE::Event.new(db)
ev.on_event('WillConnect') {|*args|
  foo
}
db.open
WIN32OLE::Event.message_loop
