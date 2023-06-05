$VERBOSE = nil

CONSTANT1 = 1
CONSTANT2 = 1
CONSTANT3 = 1
CONSTANT4 = 1
CONSTANT5 = 1

def constants
  [CONSTANT1, CONSTANT2, CONSTANT3, CONSTANT4, CONSTANT5]
end

500_000.times do
  constants

  # With previous behavior, this would cause all of the constant caches
  # associated with the constant lookups listed above to invalidate, meaning
  # they would all have to be fetched again. With current behavior, it only
  # invalidates when a name matches, so the following constant set shouldn't
  # impact the constant lookups listed above.
  INVALIDATE = true
end
