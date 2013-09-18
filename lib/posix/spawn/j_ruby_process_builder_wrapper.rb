require 'java'
require 'stringio'
require 'delegate'

module ::Process
  class JRubyPid < SimpleDelegator
    attr_accessor :jruby_process
  end

  class << self
    alias_method :orig_wait, :wait
    alias_method :orig_waitpid, :waitpid

    def wait(*args)
      if args.first.respond_to?(:jruby_process)
        javaWaitFor(args.first)
      else
        orig_wait(*args)
      end
    end

    def waitpid(*args)
      if args.first.respond_to?(:jruby_process)
        javaWaitFor(args.first)
      else
        orig_waitpid(*args)
      end
    end

    def javaWaitFor(javaPid)
      pid = javaPid.__getobj__
      exitstatus = javaPid.jruby_process.waitFor
      # set $?
      JRuby.runtime.getCurrentContext.setLastExitStatus(
        org.jruby.RubyProcess::RubyStatus.newProcessStatus(JRuby.runtime,
        exitstatus, pid))
      pid
    end
  end
end

class POSIX::Spawn::JRubyProcessBuilderWrapper
  class << self
    def spawn(*args)
      # unsupported options: :pgroup, :new_pgroup, :rlimit_, :umask, :close_others
      # IO redirection except for :in, :out, :err
      env = args[0].kind_of?(Hash) ? args.shift : {}
      options = args[-1].kind_of?(Hash) ? args.pop : {}
      chdir = options.delete(:chdir)
      chdir ||= JRuby.runtime.getCurrentDirectory

      env = ENV.merge(env) unless options[:unsetenv_others]

      # options
      stdin = options.delete(:in)
      stdout = options.delete(:out)
      stderr = options.delete(:err)

      start(chdir, env, args, stdin, stdout, stderr)
    end

    def start(pwd, env, args, stdin, stdout, stderr)
      pwd = java.io.File.new(pwd)
      argEnv = env.each_pair.map { |k, v| "#{k}=#{v}" }.to_java(:string)
      # TODO: support [[,], ...]
      args[0] = args[0][0] if args[0].is_a?(Array)
      rawArgs = args.to_java(org.jruby.runtime.builtin.IRubyObject)

      cfg = org.jruby.util.ShellLauncher::LaunchConfig.new(JRuby.runtime, rawArgs, true)

      if cfg.shouldRunInShell
        cfg.verifyExecutableForShell
      else
        cfg.verifyExecutableForDirect
      end

      aProcess = org.jruby.util.ShellLauncher.buildProcess(JRuby.runtime,
        cfg.getExecArgs, argEnv, pwd)

      handleStreamsNonblocking(aProcess, stdin, stdout, stderr)
      jruby_pid(aProcess)
    end

    def jruby_pid(process)
      pid = org.jruby.util.ShellLauncher.reflectPidFromProcess(process)
      pid = Process::JRubyPid.new(pid)
      pid.jruby_process = process
      pid
    end

    def handleStreamsNonblocking(process, stdin, stdout, stderr)
      redirect_output(process.getErrorStream, stderr)
      redirect_output(process.getInputStream, stdout)

      redirect_input(process.getOutputStream, stdin)
    end

    def patchRubyIoClose(ruby_io)
      return unless ruby_io
      class << ruby_io
        alias_method :_close, :close
        def close
        end
      end
    end

    def redirect_input(java_io, ruby_io)
      return java_io.close unless ruby_io
      patchRubyIoClose(ruby_io)
      Thread.new do
        begin
          isr = java.io.OutputStreamWriter.new(java_io)
          br = java.io.BufferedWriter.new(isr)
          begin
            ruby_io.each_char do |data|
              begin
                br.write(data, 0, data.size)
              rescue java.io.IOException # java.io.IOException: Broken pipe
                break
              end
            end
          rescue EOFError
          end
        ensure
          ruby_io._close
          begin
            br.close
          rescue java.io.IOException
          end
          isr.close
          java_io.close
        end
      end
    end

    def redirect_output(java_io, ruby_io)
      return java_io.close unless ruby_io
      patchRubyIoClose(ruby_io)
      Thread.new do
        begin
          isr = java.io.InputStreamReader.new(java_io)
          br = java.io.BufferedReader.new(isr)
          while (char = br.read) != -1
            begin
              ruby_io.putc(char)
            rescue IOError, Errno::EPIPE
              break
            end
          end
        ensure
          ruby_io._close rescue nil
          begin
            br.close
          rescue java.io.IOException
          end
          isr.close
          java_io.close
        end
      end
    end
  end
end
