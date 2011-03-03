# posix-spawn

`fork(2)` calls slow down as the parent process uses more memory due to the need
to copy page tables. In many common uses of fork(), where it is followed by one
of the exec family of functions to spawn child processes (`Kernel#system`,
`IO::popen`, `Process::spawn`, etc.), it's possible to remove this overhead by using
the use of special process spawning interfaces (`posix_spawn()`, `vfork()`, etc.)

The posix-spawn library aims to implement a subset of the Ruby 1.9 `Process::spawn`
interface in a way that takes advantage of fast process spawning interfaces when
available and provides sane fallbacks on systems that do not.

## FEATURES

 - Fast, constant-time spawn times across a variety of platforms.
 - Most of Ruby 1.9's `Process::spawn` interface under Ruby >= 1.8.7.
 - High level `POSIX::Spawn::Process` class for common IPC cases.

## BENCHMARKS

The following benchmarks illustrate time needed to fork/exec a child process at
increasing resident memory sizes on Linux 2.6 and MacOS X. Tests were run using
the [`posix-spawn-benchmark`][pb] program included with the package.

[pb]: https://github.com/rtomayko/posix-spawn/tree/master/bin

### Linux

![](https://chart.googleapis.com/chart?chbh=a,5,25&chxr=1,0,36,7&chd=t:5.77,10.37,15.72,18.31,19.73,25.13,26.70,29.31,31.44,35.49|0.86,0.82,1.06,0.99,0.79,1.06,0.84,0.79,0.93,0.94&chxs=1N**%20secs&chs=900x200&chds=0,36&chxl=0:|50%20MB|100%20MB|150%20MB|200%20MB|250%20MB|300%20MB|350%20MB|400%20MB|450%20MB|500%20MB&cht=bvg&chdl=fspawn%20%28fork%2Bexec%29|pspawn%20%28posix_spawn%29&chtt=posix-spawn-benchmark%20--graph%20--count%20500%20--mem-size%20500%20%28x86_64-linux%29&chco=1f77b4,ff7f0e&chf=bg,s,f8f8f8&chxt=x,y#.png)

`posix_spawn` is faster than `fork+exec`, and executes in constant time when
used with `POSIX_SPAWN_USEVFORK`.

`fork+exec` is extremely slow for large parent processes.

### OSX

![](https://chart.googleapis.com/chart?chxl=0:|50%20MB|100%20MB|150%20MB|200%20MB|250%20MB|300%20MB|350%20MB|400%20MB|450%20MB|500%20MB&cht=bvg&chdl=fspawn%20%28fork%2Bexec%29|pspawn%20%28posix_spawn%29&chtt=posix-spawn-benchmark%20--graph%20--count%20500%20--mem-size%20500%20%28i686-darwin10.5.0%29&chco=1f77b4,ff7f0e&chf=bg,s,f8f8f8&chxt=x,y&chbh=a,5,25&chxr=1,0,3,0&chd=t:1.95,2.07,2.56,2.29,2.21,2.32,2.15,2.25,1.96,2.02|0.84,0.97,0.89,0.82,1.13,0.89,0.93,0.81,0.83,0.81&chxs=1N**%20secs&chs=900x200&chds=0,3#.png)

`posix_spawn` is faster than `fork+exec`, but neither is affected by the size of
the parent process.

## USAGE

This library includes two distinct interfaces: a lower level process spawning
function (`POSIX::Spawn::spawn`) based on Ruby 1.9's `Process::spawn`, and a
high level class (`POSIX::Spawn::Process`) geared toward easy spawning of
processes with simple string based standard input/output/error stream handling.
The former is much more versatile, the latter requires much less code for
certain common scenarios.

### POSIX::Spawn

The `POSIX::Spawn` module (with help from the accompanying C extension)
implements a subset of the [Ruby 1.9 Process::spawn][ps] interface, largely
through the use of the [POSIX standard `posix_spawn` family of C functions][po].
These are widely supported by various UNIX operating systems.

[ps]: http://www.ruby-doc.org/core-1.9/classes/Process.html#M002230
[po]: http://pubs.opengroup.org/onlinepubs/009695399/functions/posix_spawn.html

In its simplest form, the `spawn` method can be used to execute a child process
similar to `Kernel#system`.

    pid = POSIX::Spawn.spawn('echo', 'hello world')
    status = Process.wait(pid)

The first line executes `echo(1)` with a single argument and returns the new
process's `pid`. The second line waits for the process to complete and returns a
`Process::Status` object. Note that `spawn` *does not* wait for the process to
finish execution like `system` and does not reap the status -- you must call
`Process::wait` (or equivalent) or the process will become a zombie.

The `spawn` method is actually capable of performing a variety of other tasks,
from setting up the new process's environment to redirecting arbitrary file
descriptors. The full method signature is something like this:

    spawn([env], cmdname, argv1, ..., [options])

*NOTE: many of the following examples are taken directly from the Ruby 1.9
[`Process::spawn`][ps] docs.*

If a hash is given in the first argument, `env`, the child process's environment
becomes a merge of the parent's and any modifications specified in the hash.
When a value in `env` is `nil`, the variable is deleted in the child:

    # set FOO as BAR and unset BAZ.
    pid = spawn({"FOO" => "BAR", "BAZ" => nil}, 'echo', 'hello world')

If a hash is given as `options`, it specifies a current directory and zero or
more fd redirects for the child process.

The `:chdir` key in options specifies the current directory:

    pid = spawn(command, :chdir => "/var/tmp")

The `:in`, `:out`, `:err`, a `Fixnum`, an `IO` object or an `Array` key
specifies a redirection. For example, `stderr` can be merged into `stdout` as
follows:

    pid = spawn(command, :err => :out)
    pid = spawn(command, 2 => 1)
    pid = spawn(command, STDERR => :out)
    pid = spawn(command, STDERR => STDOUT)

The hash key is a fd in the child process started by `spawn` -- the standard
error stream (`stderr`) in this case.

The hash value is a fd in the parent process that calls `spawn` -- the standard
output stream (`stdout`) in this case.

The standard input stream (stdin) can be specified by `:in`, `0` and `STDIN`.

You can also specify a filename:

    pid = spawn(command, :in => "/dev/null")   # read mode
    pid = spawn(command, :out => "/dev/null")  # write mode
    pid = spawn(command, :err => "log")        # write mode
    pid = spawn(command, 3 => "/dev/null")     # read mode

When redirecting to `stdout` or `stderr`, the files are opened in write mode;
otherwise, read mode is used.

It's also possible to control the open flags and file permissions directly
by passing an array value:

    pid = spawn(command, :in=>["file"])       # read mode is assumed
    pid = spawn(command, :in=>["file", "r"])
    pid = spawn(command, :out=>["log", "w"])  # 0644 assumed
    pid = spawn(command, :out=>["log", "w", 0600])
    pid = spawn(command, :out=>["log", File::WRONLY|File::EXCL|File::CREAT, 0600])

The array is a `[filename, open_mode, perms]` tuple. Flags can be a string or an
integer. When flags is omitted or `nil`, `File::RDONLY` is assumed. The `perms`
element should be an integer. When `perms` is omitted or `nil`, `0644` is
assumed.

Lastly, it's possible to direct an fd be closed in the child process.  This is
important for implementing `popen`-style logic and other forms of IPC between
processes using `IO.pipe`:

    rd, wr = IO.pipe
    pid = spawn('echo', 'hello world', rd => :close, :stdout => wr)
    wr.close
    output = rd.read
    Process.wait(pid)

See the `STATUS` section below for a full account of the various
`Process::spawn` features supported (and unsupported) by `POSIX::Spawn::spawn`.

### POSIX::Spawn::Process

[TODO]

## STATUS

These `Process::spawn` arguments are currently supported:

    env: hash
      name => val : set the environment variable
      name => nil : unset the environment variable
    command...:
      commandline                 : command line string which is passed to a shell
      cmdname, arg1, ...          : command name and one or more arguments (no shell)
      [cmdname, argv0], arg1, ... : command name, argv[0] and zero or more arguments (no shell)
    options: hash
      clearing environment variables:
        :unsetenv_others => true   : clear environment variables except specified by env
        :unsetenv_others => false  : don't clear (default)
      redirection:
        key:
          FD              : single file descriptor in child process
          [FD, FD, ...]   : multiple file descriptor in child process
        value:
          FD                        : redirect to the file descriptor in parent process
          :close                    : close the file descriptor in child process
          string                    : redirect to file with open(string, "r" or "w")
          [string]                  : redirect to file with open(string, File::RDONLY)
          [string, open_mode]       : redirect to file with open(string, open_mode, 0644)
          [string, open_mode, perm] : redirect to file with open(string, open_mode, perm)
        FD is one of follows
          :in     : the file descriptor 0 which is the standard input
          :out    : the file descriptor 1 which is the standard output
          :err    : the file descriptor 2 which is the standard error
          integer : the file descriptor of specified the integer
          io      : the file descriptor specified as io.fileno
      current directory:
        :chdir => str

These are currently NOT supported:

    options: hash
      process group:
        :pgroup => true or 0 : make a new process group
        :pgroup => pgid      : join to specified process group
        :pgroup => nil       : don't change the process group (default)
      resource limit: resourcename is core, cpu, data, etc.  See Process.setrlimit.
        :rlimit_resourcename => limit
        :rlimit_resourcename => [cur_limit, max_limit]
      umask:
        :umask => int
      redirection:
        value:
          [:child, FD]              : redirect to the redirected file descriptor
      file descriptor inheritance: close non-redirected non-standard fds (3, 4, 5, ...) or not
        :close_others => false : inherit fds (default for system and exec)
        :close_others => true  : don't inherit (default for spawn and IO.popen)

## ACKNOWLEDGEMENTS

Copyright (C) by [Ryan Tomayko](http://tomayko.com/about) and [Aman Gupta](https://github.com/tmm1).

See the COPYING file for more information on license and redistribution.
