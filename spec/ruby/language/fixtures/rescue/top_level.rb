# capturing in local variable at top-level

begin
  raise "message"
rescue => e
  ScratchPad << e.message
end
