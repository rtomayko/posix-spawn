require 'date'
require 'digest/md5'
require 'rake/clean'

task :default => :build

# ==========================================================
# Ruby Extension
# ==========================================================

dlext  = Config::MAKEFILE_CONFIG['DLEXT']
digest = Digest::MD5.hexdigest(`#{RUBY} --version`)

file "ext/ruby-#{digest}" do |f|
  rm_f FileList["ext/ruby-*"]
  touch f.name
end
CLEAN.include "ext/ruby-*"

file 'ext/Makefile' => FileList['ext/*.{c,h,rb}', "ext/ruby-#{digest}"] do
  chdir('ext') { ruby 'extconf.rb' }
end
CLEAN.include 'ext/Makefile', 'ext/mkmf.log'

file "ext/fastspawn.#{dlext}" => FileList["ext/Makefile"] do |f|
  sh 'cd ext && make clean && make && rm -rf conftest.dSYM'
end
CLEAN.include 'ext/*.{o,bundle,so,dll}'

file "lib/fastspawn.#{dlext}" => "ext/fastspawn.#{dlext}" do |f|
  cp f.prerequisites, "lib/", :preserve => true
end

desc 'Build the fastspawn extension'
task :build => "lib/fastspawn.#{dlext}"

# PACKAGING =================================================================

require 'rubygems'
$spec = eval(File.read('fastspawn.gemspec'))
package = "pkg/fastspawn-#{$spec.version}.gem"

desc 'Build packages'
task :package => package

directory 'pkg/'
file package => %w[pkg/ fastspawn.gemspec] + $spec.files do |f|
  sh "gem build fastspawn.gemspec"
  mv File.basename(f.name), f.name
end

# GEMSPEC HELPERS ==========================================================

def source_version
  line = File.read('lib/fastspawn.rb')[/^\s*VERSION = .*/]
  line.match(/.*VERSION = '(.*)'/)[1]
end

file 'fastspawn.gemspec' => FileList['Rakefile','lib/fastspawn.rb'] do |f|
  # read spec file and split out manifest section
  spec = File.read(f.name)
  head, manifest, tail = spec.split("  # = MANIFEST =\n")
  head.sub!(/\.version = '.*'/, ".version = '#{source_version}'")
  head.sub!(/\.date = '.*'/, ".date = '#{Date.today.to_s}'")
  # determine file list from git ls-files
  files = `git ls-files`.
    split("\n").
    sort.
    reject{ |file| file =~ /^\./ }.
    map{ |file| "    #{file}" }.
    join("\n")
  # piece file back together and write...
  manifest = "  s.files = %w[\n#{files}\n  ]\n"
  spec = [head,manifest,tail].join("  # = MANIFEST =\n")
  File.open(f.name, 'w') { |io| io.write(spec) }
  puts "updated #{f.name}"
end
