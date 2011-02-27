module FastSpawn
  VERSION = '0.1'
  extend self

  # fail fast when extension methods already defined due to twice-loading
  raise LoadError, "fastspawn extension already loaded" if method_defined?(:vspawn)

  # Spawn a child process using fast vfork + exec.
  #
  # argv - Array of command line arguments passed to exec.
  #
  # Returns the pid of the newly spawned process.
  # Raises NotImplemented when vfork is not supported on the current platform.
  def vspawn(*argv)
    raise NotImplemented
  end

  # Spawn a child process using a normal fork + exec.
  #
  # Returns the pid of the newly spawned process.
  def fspawn(*argv)
    fork do
      exec(*argv)
      exit! 1
    end
  end
end

# fastspawn extension methods replace ruby versions
require 'fastspawn.so'
