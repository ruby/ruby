::A += 1

A += 1

B::A += 1

def x; ::A ||= 1; end

def x; self::A ||= 1; end
