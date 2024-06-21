/^[a-zA-Z_0-9]*hash/,/^}/{
  s/ hval = / hval = (unsigned int)/
  s/ return / return (unsigned int)/
}
