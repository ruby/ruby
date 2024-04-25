# frozen_string_literal: true

# This is turned off because when we run with --parser=prism we explicitly turn
# off experimental warnings to make sure the output is consistent.
MSpec.register(:exclude, "Warning.[] returns default values for categories :deprecated and :experimental")

## Language
MSpec.register(:exclude, "Hash literal raises a SyntaxError at parse time when Symbol key with invalid bytes")
MSpec.register(:exclude, "Hash literal raises a SyntaxError at parse time when Symbol key with invalid bytes and 'key: value' syntax used")
MSpec.register(:exclude, "Regexps with encoding modifiers supports /e (EUC encoding) with interpolation")
MSpec.register(:exclude, "Regexps with encoding modifiers supports /e (EUC encoding) with interpolation /o")
MSpec.register(:exclude, "Regexps with encoding modifiers preserves EUC-JP as /e encoding through interpolation")
MSpec.register(:exclude, "Regexps with encoding modifiers supports /s (Windows_31J encoding) with interpolation")
MSpec.register(:exclude, "Regexps with encoding modifiers supports /s (Windows_31J encoding) with interpolation and /o")
MSpec.register(:exclude, "Regexps with encoding modifiers preserves Windows-31J as /s encoding through interpolation")
MSpec.register(:exclude, "Regexps with encoding modifiers supports /u (UTF8 encoding) with interpolation")
MSpec.register(:exclude, "Regexps with encoding modifiers supports /u (UTF8 encoding) with interpolation and /o")
MSpec.register(:exclude, "Regexps with encoding modifiers preserves UTF-8 as /u encoding through interpolation")
MSpec.register(:exclude, "A Symbol literal raises an SyntaxError at parse time when Symbol with invalid bytes")

## Core
MSpec.register(:exclude, "TracePoint#inspect returns a String showing the event, method, path and line for a :return event")
MSpec.register(:exclude, "TracePoint.new includes multiple events when multiple event names are passed as params")
MSpec.register(:exclude, "TracePoint#path equals \"(eval at __FILE__:__LINE__)\" inside an eval for :end event")

## Library
MSpec.register(:exclude, "Coverage.result returns the correct results when eval coverage is disabled")
MSpec.register(:exclude, "Coverage.start measures coverage within eval")
MSpec.register(:exclude, "Socket.gethostbyaddr using an IPv6 address with an explicit address family raises SocketError when the address is not supported by the family")
