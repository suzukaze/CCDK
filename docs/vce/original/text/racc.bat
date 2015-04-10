@echo off
if not "%~d0" == "~d0" goto WinNT
\bin\ruby -x "/bin/racc.bat" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofruby
:WinNT
"%~dp0ruby" -x "%~f0" %*
goto endofruby
#!c:/home/ruby/bin/ruby
#
# racc
#
#   Copyright (c) 1999-2002 Minero Aoki <aamine@loveruby.net>
#
#   This program is free software.
#   You can distribute/modify this program under the terms of
#   the GNU Lesser General Public License version 2 or later.
#


##### main -----------------------------------------------------

def racc_main
  opt = get_options()
  require opt['-R'] || 'racc/compiler'
  srcfn = ARGV[0]

  racc = Racc::Compiler.new
  begin
    racc_main0 racc, srcfn, opt
  rescue Racc::ParseError, Racc::ScanError, Racc::RaccError, Errno::ENOENT
    raise if racc.debug
    msg = $!.to_s
    unless /\A\d/ === msg
      msg[0,0] = ' '
    end
    $stderr.puts "#{File.basename $0}:#{srcfn}:" + msg
    exit 1
  end
end


def racc_main0( racc, srcfn, opt )
  srcstr = nil
  File.open(srcfn, 'r') {|f| srcstr = f.read }

  set_flags__before_parse racc, opt
  if opt['-P']
    prof = pcompile(racc, srcstr, srcfn) {
               set_flags__after_parse racc, opt
           }
  else
    racc.parse srcstr, srcfn
    if opt['--check-only']
      $stderr.puts 'syntax ok'
      exit 0
    end
    set_flags__after_parse racc, opt
    racc.compile
  end

  write_table_file racc, srcfn, opt

  if prof
    report_profile prof
  end

  if opt['--verbose']
    output_fn = opt['--log-file'] ||
                make_filename(opt['--output'] || srcfn, '.output')
    File.open(output_fn, 'w') {|f|
        racc.output f
    }
  end

  report_conflict racc, opt
  report_useless racc, opt
end



##### parse arg ------------------------------------------------

require 'getoptlong'
require 'racc/info'


Racc_Options = <<S

o -g --debug            - output parser for user level debugging
o -o --output-file <outfile>  file name of output [<fname>.tab.rb]
o -e --executable <rubypath>  insert #! line in output ('ruby' to default)
o -E --embedded         - output file which don't need runtime
o -l --no-line-convert  - never convert line numbers (for ruby<=1.4.3)
o -c --line-convert-all - convert line numbers also header and footer
x -s --super <super>      use <super> instead of Racc::Parser
x -r --runtime <file>     use <file> instead of 'racc/parser'
o -a --no-omit-actions  - never omit actions

o -v --verbose          - create <filename>.output file
o -O --log-file <fname>   file name of verbose output [<fname>.output]

o -C --check-only       - syntax check only
o -S --output-status    - output status time to time
o -  --no-extentions    - run without any ruby extentions
o -h --help             - print this message and quit
o -  --version          - print version and quit
o -  --runtime-version  - print runtime version and quit
o -  --copyright        - print copyright and quit

x -P -                  - report profile
x -R - <req>              require <req> instead of 'racc/libracc'             
x -D - <flags>            set (racc's) debug flags
S

module Racc
end

def get_options
  tmp = Racc_Options.collect {|line|
      next if /\A\s*\z/ === line
      disp, sopt, lopt, takearg, doc = line.strip.split(/\s+/, 5)
      a = []
      a.push lopt unless lopt == '-'
      a.push sopt unless sopt == '-'
      a.push takearg == '-' ?
             GetoptLong::NO_ARGUMENT : GetoptLong::REQUIRED_ARGUMENT
      a
  }
  getopt = GetoptLong.new(*tmp.compact)
  getopt.quiet = true

  opt = {}
  begin
    getopt.each do |name, arg|
      raise GetoptLong::InvalidOption,
              "#{File.basename $0}: #{name} given twice" if opt.key? name
      opt[name] = arg.empty? ? true : arg
    end
  rescue GetoptLong::AmbigousOption, GetoptLong::InvalidOption,
         GetoptLong::MissingArgument, GetoptLong::NeedlessArgument
    usage 1, $!.message
  end

  usage 0 if opt['--help']

  if opt['--version']
    puts "racc version #{Racc::Version}"
    exit 0
  end
  Racc.const_set :Racc_No_Extentions, opt['--no-extentions']
  if opt['--runtime-version']
    require 'racc/parser'
    printf "racc runtime version %s (rev. %s); %s\n",
           Racc::Parser::Racc_Runtime_Version,
           Racc::Parser::Racc_Runtime_Revision,
           if Racc::Parser.racc_runtime_type == 'ruby'
             sprintf('ruby core version %s (rev. %s)',
                     Racc::Parser::Racc_Runtime_Core_Version_R,
                     Racc::Parser::Racc_Runtime_Core_Revision_R)
           else
             sprintf('c core version %s (rev. %s)',
                     Racc::Parser::Racc_Runtime_Core_Version_C,
                     Racc::Parser::Racc_Runtime_Core_Revision_C)
           end
    exit 0
  end
  if opt['--copyright']
    puts "racc version #{Racc::Version}"
    puts "#{Racc::Copyright} <aamine@loveruby.net>"
    exit 0
  end

  usage(1, 'no grammar file given') if ARGV.empty?
  usage(1, 'too many grammar files given') if ARGV.size > 1

  opt['--line-convert'] = true
  if opt['--no-line-convert']
    opt['--line-convert'] = opt['--line-convert-all'] = false
  end

  opt['--omit-action'] = true
  if opt['--no-omit-action']
    opt['--omit-action'] = false
  end

  opt
end


def usage( status, msg = nil )
  f = (status == 0 ? $stdout : $stderr)
  f.puts "#{File.basename $0}: #{msg}" if msg
  f.print(<<EOS)

Usage: racc [options] <grammar file>

Options:
EOS

  Racc_Options.each do |line|
    if /\A\s*\z/ === line
      f.puts
      next
    end

    disp, sopt, lopt, takearg, doc = line.strip.split(/\s+/, 5)
    if disp == 'o'
      sopt = nil if sopt == '-'
      lopt = nil if lopt == '-'
      opt = [sopt, lopt].compact.join(',')

      takearg = nil if takearg == '-'
      opt = [opt, takearg].compact.join(' ')

      f.printf "%-27s %s\n", opt, doc
    end
  end

  exit status
end



##### compile ----------------------------------------------

def set_flags__before_parse( racc, opt )
  racc.verbose = opt['--output-status']

  if opt['-D'] and /p/ === opt['-D']
    racc.d_parse = true
  end
end

def set_flags__after_parse( racc, opt )
  # overwrite source's
  racc.debug_parser = opt['--debug']
  racc.convert_line = opt['--line-convert']
  racc.omit_action  = opt['--omit-action']

  if opt['-D'] or $DEBUG
    optd = opt['-D'] || ''
    $stdout.sync = true
    racc.debug   = true
    racc.d_rule  = true if /r/ === optd
    racc.d_token = true if /t/ === optd
    racc.d_state = true if /s/ === optd
    racc.d_la    = true if /l/ === optd
    racc.d_prec  = true if /c/ === optd
  end
end


##### profile

def pcompile( racc, srcstr, srcfn )
  times = []
  times.push [ 'parse',   get_lap{ racc.parse(srcstr, srcfn) } ]
  yield
  times.push [ 'state',   get_lap{ racc.nfa } ]
  times.push [ 'resolve', get_lap{ racc.dfa } ]
  times
end

def get_lap
  begt = Time.times.utime
  yield
  endt = Time.times.utime
  endt - begt
end

def report_profile( prof )
  out = $stderr

  whole = 0
  prof.each do |arr|
    whole += arr[1]
  end
  whole = 0.01 if whole == 0

  out.puts '--task-----------+--sec------+---%-'

  prof.each do |arr|
    name, time = arr
    out.printf("%-19s %s %3d%%\n",
               name, pjust(time,4,4), (time/whole * 100).to_i)
  end

  out.puts '-----------------+-----------+-----'
  out.printf("%-20s%s\n",
             'total', pjust(whole,4,4))
end

def pjust( num, i, j )
  m = /(\d+)(\.\d+)?/.match(num.to_s)
  str = m[1].rjust(i)
  if m[2]
    str << m[2].ljust(j+1)[0,j+1]
  end

  str
end



##### output -----------------------------------------------

require 'racc/rubyloader'


def write_table_file( racc, srcfn, opt )
  tabfn = opt['--output-file'] || make_filename(srcfn, '.tab.rb')

  RaccTableFile.new(tabfn, srcfn, opt['--line-convert']) {|f|
      f.shebang opt['--executable'] if opt['--executable']
      f.notice
      f.require opt['--embedded'], opt['--runtime'] || 'racc/parser'
      f.header opt['--line-convert-all']
      f.parser_class(racc.parser.class_name,
                     opt['--super'] || racc.parser.super_class || 'Racc::Parser') {
          f.inner
          racc.source f.file
      }
      f.footer opt['--line-convert-all']
  }

  if opt['--executable']
    File.chmod 0755, tabfn
  else
    File.chmod 0644, tabfn
  end
end

def make_filename( fname, suffix )
  fname.sub(/(?:\..*?)?\z/, suffix)
end


class RaccTableFile

  def initialize( tabfn, srcfn, c )
    @tabfn = tabfn
    @srcfn = srcfn
    @convline = c

    @header_labels = %w( header prepare )
    @inner_labels  = %w( inner )
    @footer_labels = %w( footer driver )

    @is_top = false
    @uniq = {}

    init_user_code

    File.open(tabfn, 'w') {|f|
        @f = f
        yield self
    }
  end

  def file
    @f
  end


  RUBY_PATH = ::Config::CONFIG['bindir'] + '/' +
              ::Config::CONFIG['ruby_install_name']

  def shebang( path )
    @f.print "#!#{path == 'ruby' ? RUBY_PATH : path}\n"
  end


  def notice
    @f.print <<EOS
#
# DO NOT MODIFY!!!!
# This file is automatically generated by racc #{Racc::Version}
# from racc grammer file "#{@srcfn}".
#
EOS
  end


  def require( embed_p, parser_rb )
    if embed_p
      @f.print <<EOS
#
# #{@tabfn}: generated by racc (runtime embedded)
#

EOS
      is_top {
          embed 'racc/parser.rb'
      }
      @f.puts
    else
      @f.puts
      @f.puts  "require '#{parser_rb}'"
      @f.puts
    end
  end


  def parser_class( classname, superclass )
    @f.puts

    mods = classname.split('::')
    real = mods.pop
    mods.each_with_index do |m,i|
      @f.puts  "#{'  ' * i}module #{m}"
      @f.puts
    end
    @f.puts "#{'  ' * mods.size}class #{real} < #{superclass}"

    yield

    @f.puts "#{'  ' * mods.size}end   \# class #{real}"
    mods.reverse.each_with_index do |m,i|
      @f.puts
      @f.puts  "#{'  ' * (mods.size - i - 1)}end   \# module #{m}"
    end
  end


  def header( conv )
    is_top {
        add_part conv, @header_labels
    }
  end

  def inner
    add_part @convline, @inner_labels
  end

  def footer( conv )
    is_top {
        add_part conv, @footer_labels
    }
  end


  private


  ###
  ### init
  ###

  def init_user_code
    @usercode = Racc::GrammarFileParser.get_usercode(@srcfn)
    check_dup_ucode
  end

  def check_dup_ucode
    [ @header_labels, @inner_labels, @footer_labels ].each do |names|
      a = names.select {|n| @usercode[n] }
      if a.size > 1
        raise Racc::RaccError,
                "'#{a.join %<' and '>}' used at same time; must be only one"
      end
    end
  end


  ###
  ### embed
  ###

  def embed( rbfile )
    @f.print <<EOS
###### #{rbfile}

unless $".index '#{rbfile}'
$".push '#{rbfile}'
EOS
    add_file RubyLoader.find_feature(rbfile)
    @f.puts "end   # end of #{rbfile}"
  end


  ###
  ### part
  ###

  def add_part( convp, names )
    str, lineno, fnames = getent(names)
    convert_line(convp) {
        add str, @srcfn, lineno if str and not str.strip.empty?
    }
    fnames.each {|n| add_file n } if fnames
  end

  def getent( names )
    names.each do |n|
      return @usercode[n] if @usercode[n]
    end
    nil
  end

  def convert_line( b )
    save, @convline = @convline, b
    yield
    @convline = save
  end


  ###
  ### low level code
  ###

  def add_file( fname )
    File.open(fname) {|f|
        add f.read, fname, 1
    }
  end

  def add( str, fn, lineno )
    @f.puts
    if @convline
      surrounding_by_eval(fn, str, lineno) {
          @f.puts str
      }
    else
      @f.puts str
    end
  end


  def surrounding_by_eval( nm, str, lineno )
    sep = makesep(nm, str)
    @f.print 'self.class.' if toplevel?
    @f.puts "module_eval <<'#{sep}', '#{nm}', #{lineno}"
    yield
    @f.puts sep
  end

  def is_top
    @is_top = true
    yield
    @is_top = false
  end

  def toplevel?
    @is_top
  end

  def makesep( nm, str )
    sep = uniqlabel(nm)
    sep *= 2 while str.index(sep)
    sep
  end

  def uniqlabel( nm )
    ret = "..end #{nm} modeval..id"
    srand
    5.times do
      ret << sprintf('%02x', rand(255))
    end
    ret << sprintf('%02x', rand(255)) while @uniq[ret]
    @uniq[ret] = true
    ret
  end

end   # class RaccTableFile



##### report -----------------------------------------------

def report_conflict( racc, opt )
  sr = 0
  rr = 0
  racc.statetable.each do |st|
    sr += st.srconf.size if st.srconf
    rr += st.rrconf.size if st.rrconf
  end

  if opt['-D'] and /o/ === opt['-D']
    debugout {|f|
      f.print "ex#{racc.ruletable.expect}\n"
      f.print "sr#{sr}\n" if sr > 0
      f.print "rr#{rr}\n" if rr > 0
    }
    return
  end
      
  ex = racc.ruletable.expect
  if (sr > 0 or ex) and sr != ex
    $stderr.puts "#{sr} shift/reduce conflicts"
  end
  if rr > 0
    $stderr.puts "#{rr} reduce/reduce conflicts"
  end
end


def report_useless( racc, opt )
  nt = 0
  rl = 0
  racc.symboltable.each_nonterm do |t|
    if t.useless?
      nt += 1
    end
  end
  racc.ruletable.each do |r|
    if r.useless?
      rl += 1
    end
  end

  if opt['-D'] and /o/ === opt['-D']
    debugout('a') {|f|
      f.print "un#{nt}\n" if nt > 0
      f.print "ur#{rl}\n" if rl > 0
    }
    return
  end

  if nt > 0 or rl > 0
    $stderr.printf "%s%s%s\n",
                   nt > 0                 ? "#{nt} useless nonterminals" : '',
                   ((nt > 0) && (rl > 0)) ? ' and '                     : '',
                   rl > 0                 ? "#{rl} useless rules"        : ''
  end

  if racc.ruletable.start.useless?
    $stderr.puts 'fatal: start symbol does not derive any sentence'
  end
end

def debugout( flag = 'w', &block )
  File.open("log/#{File.basename(ARGV[0])}", flag, &block)
end


##### entry point ------------------------------------------

racc_main
__END__
:endofruby
