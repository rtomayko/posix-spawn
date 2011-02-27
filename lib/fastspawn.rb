module FastSpawn
  VERSION = '0.1'
  extend self

  # fail fast when extension methods already defined due to twice-loading
  raise LoadError, "fastspawn extension already loaded" if method_defined?(:vspawn)
end

# fastspawn extension methods replace ruby versions
require 'fastspawn.so'
