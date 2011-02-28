module FastSpawn
  VERSION = '0.1'
  extend self

  # fail fast when extension methods already defined due to twice-loading
  raise LoadError, "fastspawn extension already loaded" if method_defined?(:vspawn)

  # Spawn a child process using posix_spawn.
  #
  # argv - Array of command line arguments passed to exec.
  #
  # Returns the pid of the newly spawned process.
  # Raises NotImplemented when pfork is not supported on the current platform.
  def pspawn(*argv)
    env, argv, options = extract_process_spawn_arguments(*argv)
    _pspawn(env, argv, options)
  end

  # Spawn a child process using a normal fork + exec.
  #
  # Returns the pid of the newly spawned process.
  def fspawn(*argv)
    env, argv, options = extract_process_spawn_arguments(*argv)
    fork do
      exec(*argv)
      exit! 1
    end
  end

  # Turns the various varargs incantations supported by Process::spawn into a
  # simple [env, argv, options] tuple. This just makes life easier for the
  # extension functions.
  #
  # The following method signature is supported:
  #   Process::spawn([env], command, ..., [options])
  #
  # The env and options hashes are optional. The command may be a variable
  # number of strings or an Array full of strings that make up the new process's
  # argv.
  #
  # Returns an [env, argv, options] tuple. All elements are guaranteed to be
  # non-nil. When no env or options are given, empty hashes are returned.
  def extract_process_spawn_arguments(*args)
    # pop the options hash off the end if it's there
    options =
      if args[-1].respond_to?(:to_hash)
        args.pop.to_hash
      else
        {}
      end

    # shift the environ hash off the front if it's there
    env =
      if args[0].respond_to?(:to_hash)
        args.shift.to_hash
      else
        {}
      end
    env.merge!(options.delete(:env)) if options.key?(:env)

    # remaining arguments are the argv. it's possible for this to be an single
    # element array so pull it out if so.
    argv =
      if args.size == 1 && args[0].respond_to?(:to_ary)
        args[0]
      else
        args
      end

    flatten_process_spawn_options!(options)
    [env, argv, options]
  end

  # Convert { [fd1, fd2, ...] => (:close|fd) } options to individual keys,
  # like: { fd1 => :close, fd2 => :close }. This just makes life easier for the
  # spawn implementations.
  #
  # options - The options hash. This is modified in place.
  #
  # Returns the modified options hash.
  def flatten_process_spawn_options!(options)
    options.each do |key, value|
      if key.respond_to?(:to_ary)
        key.to_ary.each { |fd| options[fd] = value }
        options.delete(key)
      end
    end
  end
end

# fastspawn extension methods replace ruby versions
require 'fastspawn.so'
