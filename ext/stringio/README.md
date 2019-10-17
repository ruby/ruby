# StringIO

Pseudo `IO` class from/to `String`.

This library is based on MoonWolf version written in Ruby.  Thanks a lot.

## Differences to `IO`

* `fileno` raises `NotImplementedError`.
* encoding conversion is not implemented, and ignored silently.
