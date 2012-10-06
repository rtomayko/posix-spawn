task :default => :test

# ==========================================================
# Packaging
# ==========================================================

GEMSPEC = eval(File.read('posix-spawn.gemspec'))

require 'rake/gempackagetask'
Rake::GemPackageTask.new(GEMSPEC) do |pkg|
end

# ==========================================================
# Ruby Extension
# ==========================================================

require 'rake/extensiontask'
Rake::ExtensionTask.new('posix_spawn_ext', GEMSPEC) do |ext|
  ext.ext_dir = 'ext'
end
task :build => :compile

# ==========================================================
# Testing
# ==========================================================

require 'rake/testtask'
Rake::TestTask.new 'test' do |t|
  t.test_files = FileList['test/test_*.rb']
end

desc 'Run some benchmarks'
task :benchmark do
  ruby '-Ilib', 'bin/posix-spawn-benchmark'
end

unless RUBY_PLATFORM =~ /(mswin|mingw|cygwin|bccwin)/
  task :test => :build
  task :benchmark => :build
end
