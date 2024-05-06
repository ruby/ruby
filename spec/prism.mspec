# frozen_string_literal: true

# We are missing emitting some :end event inside eval; we need more
# investigation here.
MSpec.register(:exclude, "TracePoint#path equals \"(eval at __FILE__:__LINE__)\" inside an eval for :end event")

# We need to respect the eval coverage setting.
MSpec.register(:exclude, "Coverage.result returns the correct results when eval coverage is disabled")
