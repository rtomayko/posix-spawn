# coding: UTF-8

require 'test_helper'

class ChildTest < Minitest::Test
  include POSIX::Spawn

  def test_sanity
    assert_same POSIX::Spawn::Child, Child
  end

  def test_argv_array_execs
    p = Child.new('printf', '%s %s %s', '1', '2', '3 4')
    assert p.success?
    assert_equal "1 2 3 4", p.out
  end

  def test_argv_string_uses_sh
    p = Child.new("echo via /bin/sh")
    assert p.success?
    assert_equal "via /bin/sh\n", p.out
  end

  def test_stdout
    p = Child.new('echo', 'boom')
    assert_equal "boom\n", p.out
    assert_equal "", p.err
  end

  def test_stderr
    p = Child.new('echo boom 1>&2')
    assert_equal "", p.out
    assert_equal "boom\n", p.err
  end

  def test_status
    p = Child.new('exit 3')
    assert !p.status.success?
    assert_equal 3, p.status.exitstatus
  end

  def test_env
    p = Child.new({ 'FOO' => 'BOOYAH' }, 'echo $FOO')
    assert_equal "BOOYAH\n", p.out
  end

  def test_chdir
    p = Child.new("pwd", :chdir => File.dirname(Dir.pwd))
    assert_equal File.dirname(Dir.pwd) + "\n", p.out
  end

  def test_input
    input = "HEY NOW\n" * 100_000 # 800K
    p = Child.new('wc', '-l', :input => input)
    assert_equal 100_000, p.out.strip.to_i
  end

  def test_max
    assert_raises MaximumOutputExceeded do
      Child.new('yes', :max => 100_000)
    end
  end

  def test_max_with_child_hierarchy
    assert_raises MaximumOutputExceeded do
      Child.new('/bin/sh', '-c', 'yes', :max => 100_000)
    end
  end

  def test_max_with_stubborn_child
    assert_raises MaximumOutputExceeded do
      Child.new("trap '' TERM; yes", :max => 100_000)
    end
  end

  def test_max_with_partial_output
    p = Child.build('yes', :max => 100_000)
    assert_nil p.out
    assert_raises MaximumOutputExceeded do
      p.exec!
    end
    assert_output_exceeds_repeated_string("y\n", 100_000, p.out)
  end

  def test_max_with_partial_output_long_lines
    p = Child.build('yes', "nice to meet you", :max => 10_000)
    assert_raises MaximumOutputExceeded do
      p.exec!
    end
    assert_output_exceeds_repeated_string("nice to meet you\n", 10_000, p.out)
  end

  def test_timeout
    start = Time.now
    assert_raises TimeoutExceeded do
      Child.new('sleep', '1', :timeout => 0.05)
    end
    assert (Time.now-start) <= 0.2
  end

  def test_timeout_with_child_hierarchy
    assert_raises TimeoutExceeded do
      Child.new('/bin/sh', '-c', 'sleep 1', :timeout => 0.05)
    end
  end

  def test_timeout_with_partial_output
    start = Time.now
    p = Child.build('echo Hello; sleep 1', :timeout => 0.05)
    assert_raises TimeoutExceeded do
      p.exec!
    end
    assert (Time.now-start) <= 0.2
    assert_equal "Hello\n", p.out
  end

  def test_lots_of_input_and_lots_of_output_at_the_same_time
    input = "stuff on stdin \n" * 1_000
    command = "
      while read line
      do
        echo stuff on stdout;
        echo stuff on stderr 1>&2;
      done
    "
    p = Child.new(command, :input => input)
    assert_equal input.size, p.out.size
    assert_equal input.size, p.err.size
    assert p.success?
  end

  def test_input_cannot_be_written_due_to_broken_pipe
    input = "1" * 100_000
    p = Child.new('false', :input => input)
    assert !p.success?
  end

  def test_utf8_input
    input = "hålø"
    p = Child.new('cat', :input => input)
    assert p.success?
  end

  def test_utf8_input_long
    input = "hålø" * 10_000
    p = Child.new('cat', :input => input)
    assert p.success?
  end

  ##
  # Assertion Helpers

  def assert_output_exceeds_repeated_string(str, len, actual)
    assert_operator actual.length, :>=, len

    expected = (str * (len / str.length + 1)).slice(0, len)
    assert_equal expected, actual.slice(0, len)
  end
end
