def f &b; end

def f (((a))); end

def f ((*)); end

def f ((*, p)); end

def f ((*r)); end

def f ((*r, p)); end

def f ((a, *)); end

def f ((a, *, p)); end

def f ((a, *r)); end

def f ((a, *r, p)); end

def f ((a, a1)); end

def f (foo: 1, &b); end

def f (foo: 1, bar: 2, **baz, &b); end

def f **baz, &b; end

def f *, **; end

def f *r, &b; end

def f *r, p, &b; end

def f ; end

def f a, &b; end

def f a, *r, &b; end

def f a, *r, p, &b; end

def f a, o=1, &b; end

def f a, o=1, *r, &b; end

def f a, o=1, *r, p, &b; end

def f a, o=1, p, &b; end

def f foo:
; end

def f foo: -1
; end

def f o=1, &b; end

def f o=1, *r, &b; end

def f o=1, *r, p, &b; end

def f o=1, p, &b; end
