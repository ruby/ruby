require 'win32ole'
ie = WIN32OLE.new('InternetExplorer.Application')
ie.visible = true
WIN32OLE_EVENT.message_loop
sleep 0.2
ev = WIN32OLE_EVENT.new(ie)

ev.on_event('BeforeNavigate2') {|*args|
  foo
}
ie.navigate(ARGV.shift)
