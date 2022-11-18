#!/bin/sh

echo &&
CMD='../build/miniruby fixnums.rb sorted' && echo "\$ $CMD" && $CMD &&
CMD='./fixnums.rb sorted' && echo "\$ $CMD" && $CMD &&
CMD='../build/miniruby fixnums.rb 1' && echo "\$ $CMD" && $CMD &&
CMD='./fixnums.rb 1' && echo "\$ $CMD" && $CMD &&
CMD='../build/miniruby flonums.rb sorted' && echo "\$ $CMD" && $CMD &&
CMD='./flonums.rb sorted' && echo "\$ $CMD" && $CMD &&
CMD='../build/miniruby flonums.rb 1' && echo "\$ $CMD" && $CMD &&
CMD='./flonums.rb 1' && echo "\$ $CMD" && $CMD
CMD='../build/miniruby noflonums.rb sorted' && echo "\$ $CMD" && $CMD &&
CMD='./noflonums.rb sorted' && echo "\$ $CMD" && $CMD &&
CMD='../build/miniruby noflonums.rb 1' && echo "\$ $CMD" && $CMD &&
CMD='./noflonums.rb 1' && echo "\$ $CMD" && $CMD
