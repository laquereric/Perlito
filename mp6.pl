package main;

use FindBin '$Bin';
use lib ("$Bin/lib5");
use strict;

BEGIN {
    $::_V6_COMPILER_NAME    = 'MiniPerl6';
    $::_V6_COMPILER_VERSION = '3.0';
}

use MiniPerl6::Perl5::Runtime;

package Main;
use MiniPerl6::Perl5::Emitter;
use MiniPerl6::Grammar;
use MiniPerl6::Grammar::Regex;
use MiniPerl6::Emitter::Token;

my ( @switch_e, $source, $source_filename, $result );
my @comp_unit;
my $backend = 'perl5';
my $tmp_filename = 'tmp';
my @cmd;
my $execute = 1;
my $compile_to_bin = 0;
my $verbose = 0;
my $lib_spec = '';
my @args = @ARGV;
while (@args) {
    if ( $args[0] eq '-v' || $args[0] eq '--verbose' ) {
        $verbose = 1;
        shift @args;
        redo;
    }
    if ( $args[0] eq '-V' || $args[0] eq '--version' ) {
        print "$::_V6_COMPILER_NAME $::_V6_COMPILER_VERSION\n";
        exit;
    }
    if ( $args[0] eq '-h' || $args[0] eq '--help') {
        print "$::_V6_COMPILER_NAME $::_V6_COMPILER_VERSION
mp6 [switches] [programfile]
  switches:
    -h --help
    -v --verbose
    -V --version
    -e program      one line of program (omit programfile)
    -Ctarget        compile to target backend: go, js, lisp, parrot, perl5
        options:
        -Cgo           compile to Go source code
        -Cjs           compile to Javascript source code
        -Clisp         compile to Lisp source code
        -Cparrot       compile to PIR source code
        -Cperl5        compile to Perl 5 source code
        -Cast-perl6    dump the ast in Perl 6 format
        -Cast-json     dump the ast in JSON format
        -Cast-perl5    dump the ast in Perl 5 format
        -Cgo-bin       create a binary executable file using Go (doesn't run it)
        -Clisp-bin     create a binary executable file using SBCL Lisp (doesn't run it) 
        -Cjava-class   create a Java .class (doesn't run it)
    -Btarget        run in target backend: go, js, lisp, parrot, perl5
        options:
        -Bgo           run in Go (this also creates a binary executable)
        -Bjs           run in V8 (Javascript)
        -Blisp         run in SBCL (Lisp)
        -Bparrot       run in Parrot
        -Bperl5        run in Perl 5 source code
        -Brhino        run in Rhino (Javascript)
        -Bv8           run in V8 (Javascript)
        -Bspidermonkey run in SpiderMonkey (Javascript)
";
        exit;
    }
    if ( $args[0] eq '-B' || $args[0] eq '-C' ) {
        if ( @args > 1 ) {
            $args[1] = $args[0] . $args[1];
            shift @args;
        }
        else {
            die("Missing argument for $args[0] option");
        }
    } 
    if ( $args[0] =~ /^-B(.*)/ ) {
        $execute = 1;
        $backend = $1;
        shift @args;
        redo;
    }
    if ( $args[0] =~ /^-C(.*?)(-bin)?$/ ) {
        $execute = 0;
        $backend = $1;
        $compile_to_bin = $2 ? 1 : 0;
        shift @args;
        redo;
    }
    if ( $args[0] eq '-e' ) {
        my ($switch, $source) = (shift @args, shift @args);
        push @switch_e, $source;
        redo;
    }
    last;
}

if ( $backend eq 'js'    ) { 
    @cmd = ('v8'); 
    $lib_spec = 'Javascript';
}
if ( $backend eq 'java-class' ) { 
    @cmd = qw/java org.mozilla.javascript.tools.jsc.Main -opt 9/;
    $backend = 'js';
    $lib_spec = 'Javascript';
    $execute = 1;
}
if ( $backend eq 'rhino' ) { 
    @cmd = qw/java org.mozilla.javascript.tools.shell.Main/; 
    $backend = 'js';
    $lib_spec = 'Javascript';
}
if ( $backend eq 'spidermonkey' ) { 
    @cmd = qw/spidermonkey/; 
    $backend = 'js';
    $lib_spec = 'Javascript';
}
if ( $backend eq 'v8'    ) { 
    @cmd = ('v8');    
    $backend = 'js';
    $lib_spec = 'Javascript';
}
if ( $backend eq 'go' ) {
    $lib_spec = 'Go';
}
if ( $backend eq 'lisp' ) {
    $lib_spec = 'Lisp';
}

$source_filename = shift @args if @args;

if ( $verbose ) {
    warn "compilation parameters:\n";
    warn "\tbackend         '$backend'\n";
    warn "\ttmp_filename    '$tmp_filename'\n";
    warn "\texecute         '$execute'\n";
    warn "\tsource_filename '$source_filename'\n";
    warn "\tBin             '$::Bin'\n";
    warn "\tcmd             '@cmd'\n";
    warn "\tlibspec         '$lib_spec'\n";
    warn "\te               '${_}'\n" for @switch_e;
}

if (@switch_e) {
    $source = join('; ', @switch_e);
}
elsif ($source_filename) {
    open FILE, $source_filename
      or die "Cannot read $source_filename\n";
    local $/ = undef;
    $source = <FILE>;
    close FILE;
    warn "read " . length($source) . " chars from $source_filename\n" if $verbose;
}
else {
    warn "reading input from STDIN\n" if $verbose;
    local $/ = undef;
    $source = <STDIN>;
}

if ( $source_filename =~ /\.p5ast$/ ) {
    # source code was precompiled to AST, dumped as a perl5 structure
    warn "input format is precompiled AST\n" if $verbose;
    @comp_unit = @{ eval $source };
}
else {
    if ( !$source_filename ) {
        # Kludge - make an implicit Main explicit.
        warn "adding implicit 'Main'\n" if $verbose && $source !~ /class/;
        $source = "class Main { $source }" if $source !~ /class/;
    }

    if  (  $backend eq 'go' 
        || $backend eq 'js'
        || ( $backend eq 'lisp' && $execute )
        ) 
    {
        # TODO - recursive 'use'
        my %module;
        my $precompiled;
        my $load_module = sub {
            my $module_name = shift;
            warn "load module: $module_name\n" if $verbose;
            return 1 if $module{$module_name};
            my $filename = $module_name;
            $filename =~ s{::}{/}g;
            $filename = $::Bin . "/libast-perl5/${filename}.p5ast";
            for (1) {
                my $has_ast = open FILE, $filename;
                if ( $has_ast ) {
                    # reuse Prelude AST if available
                    local $/ = undef;
                    my $ast = <FILE>;
                    close FILE;
                    if ( length($ast) ) {
                        push @comp_unit, @{ eval $ast };
                        warn "Error loading $filename: $@" if $@;
                        warn "included $module_name ast\n" if $verbose;
                    }
                    else {
                        $has_ast = 0;
                        close(FILE);
                        warn "$filename is empty, removing broken file";
                        unlink $filename;
                    }
                }
                else {
                    if ( !$precompiled) {
                        warn "now compiling MiniPerl6 source code to AST\n" if $verbose;
                        system( ". util-perl5/update-ast-perl5.sh" );
                        $precompiled = 1;
                        redo;
                    }
                    die "can't load module $module_name. Looking in: $filename\n";
                }
            }
            return 1;
        };
        my $pos = 0;
        $load_module->( "MiniPerl6::${lib_spec}::Prelude" );
        while ( $pos < length($source) ) {
            warn "parsing at pos $pos\n" if $verbose;
            my $p = MiniPerl6::Grammar->comp_unit( $source, $pos );
            for my $use (  
                map  { $_->{mod} } 
                grep { $_->isa("Use") } @{$$p->{body}} )
            {
                $load_module->($use);
            }
            push @comp_unit, $$p;
            $pos = $p->to;
        }
    }
    else {
        my $pos = 0;
        while ( $pos < length($source) ) {
            warn "parsing at pos $pos\n" if $verbose;
            my $p = MiniPerl6::Grammar->comp_unit( $source, $pos );
            push @comp_unit, $$p;
            $pos = $p->to;
        }
    }
}

warn "starting emitter phase\n" if $verbose;
if ( $backend eq 'lisp' ) {
    require MiniPerl6::Lisp::Emitter;
    $result .=  ";; Do not edit this file - Generated by $::_V6_COMPILER_NAME $::_V6_COMPILER_VERSION\n";
    $result .= CompUnit::emit_lisp_program( \@comp_unit );

    if ( $execute || $compile_to_bin ) {
        open( OUT, '>', $tmp_filename . '.lisp' )
          or die "Cannot write to ${tmp_filename}.lisp\n";

        my $filename = "lib/MiniPerl6/Lisp/Runtime.lisp";
        warn "reading lisp runtime: $filename\n" if $verbose;
        open FILE, $filename
          or die "Cannot read Lisp runtime: $filename";
        local $/ = undef;
        my $lib = <FILE>;
        print OUT $lib, "\n";

        $filename = "liblisp/MiniPerl6/Lisp/Prelude.lisp";
        warn "reading lisp prelude: $filename\n" if $verbose;
        open FILE, $filename
          or die "Cannot read Lisp prelude: $filename";
        $lib = <FILE>;
        print OUT $lib, "\n";

        print OUT $result, "\n";

        if ( $compile_to_bin ) {
            print OUT
                '(sb-ext:save-lisp-and-die "tmp-lisp" :toplevel \'compiler-main :executable t )';
            warn "TODO - Lisp compile_to_bin";
        }

        close(OUT);

        warn "calling lisp compiler\n" if $verbose;
        exec( "sbcl", "--script", "$tmp_filename.lisp", @args )
            or die "can't execute";
    }
}
elsif ( $backend eq 'parrot' ) {
    require MiniPerl6::Parrot::Emitter;
    $result .=  "# Do not edit this file - Generated by $::_V6_COMPILER_NAME $::_V6_COMPILER_VERSION\n";
    for my $p ( @comp_unit ) {
        $result .=  $p->emit_parrot() . "\n";
    }

    if ( $execute ) {
        open( OUT, '>', $tmp_filename . '.pir' )
          or die "Cannot write to ${tmp_filename}.pir\n";
        print OUT $result;
        close(OUT);
        warn "calling parrot compiler\n" if $verbose;
        exec( "parrot", "$tmp_filename.pir", @args )
            or die "can't execute";
    }
}
elsif ( $backend eq 'js' ) {
    require MiniPerl6::Javascript::Emitter;
    $result .=  "// Do not edit this file - Generated by $::_V6_COMPILER_NAME $::_V6_COMPILER_VERSION\n";
    for my $p ( @comp_unit ) {
        $result .=  $p->emit_javascript() . "\n";
    }

    if ( $execute ) {
        open( OUT, '>', $tmp_filename . '.js' )
          or die "Cannot write to ${tmp_filename}.js\n";
        my $inc;

        for my $lib_source_filename ( 'lib/MiniPerl6/Javascript/Runtime.js', 'libjs/MiniPerl6/Javascript/Prelude.js' ) {
            $inc .= "// include file: $lib_source_filename\n";
            open FILE, $::Bin . '/' . $lib_source_filename
              or die "Cannot read $::Bin/$lib_source_filename\n";
            local $/ = undef;
            $inc .= <FILE>;
            close FILE;
            $inc .= "\n// end include file: $lib_source_filename\n";
        }

        print OUT $inc, $result;
        close(OUT);
        my @extra_args;
        if ( $cmd[0] eq 'v8' && @args ) {
            @extra_args = ("--") 
        }
        my @exec = ( @cmd, "$tmp_filename.js", @extra_args, @args );
        warn "calling javascript compiler: @exec\n" if $verbose;
        exec( @exec )
            or die "can't execute";
    }
}
elsif ( $backend eq 'go' ) {
    require MiniPerl6::Go::Emitter;
    $result .=  "// Do not edit this file - Generated by $::_V6_COMPILER_NAME $::_V6_COMPILER_VERSION\n";

    my $lib_source_filename = 'lib/MiniPerl6/Go/Runtime.go';
    $result .= "// include file: $lib_source_filename\n";
    open FILE, $::Bin . '/' . $lib_source_filename
      or die "Cannot read $::Bin/$lib_source_filename\n";
    local $/ = undef;
    $result .= <FILE>;
    close FILE;
    $result .= "// end include file: $lib_source_filename\n";

    $result .= CompUnit::emit_go_program( \@comp_unit );

    if ( $execute || $compile_to_bin ) {
        open( OUT, '>', $tmp_filename . '.go' )
          or die "Cannot write to ${tmp_filename}.go\n";
        print OUT $result;
        close(OUT);
        unlink $tmp_filename . '.6';
        unlink '6.out';
        warn "calling go compiler\n" if $verbose;
        my $result = `6g $tmp_filename.go`;
        warn "go compiler: $result\n" if $verbose && $result;
        $result = `6l $tmp_filename.6`;
        warn "go linker: $result\n" if $verbose && $result;
    }
    if ( $execute ) {
        warn "now executing\n" if $verbose;
        exec("./6.out", @args)
            or die "can't execute";
    }
}
elsif ( $backend eq 'perl5' ) {
    $result .=  "# Do not edit this file - Generated by $::_V6_COMPILER_NAME $::_V6_COMPILER_VERSION\n";
    $result .=  "use v5;\n";
    $result .=  "use strict;\n";
    $result .=  "use MiniPerl6::Perl5::Runtime;\n";
    $result .=  "our \$MATCH = MiniPerl6::Match->new();\n";
    $result .= CompUnit::emit_perl5_program( \@comp_unit );
    $result .=  "1;\n";

    if ( $execute ) {
        local @ARGV = @args;
        eval $result;
        warn $@ if $@;
    }
}
elsif ( $backend eq 'ast-perl6' ) {
    $result .=  Main::perl( \@comp_unit ) . "\n";
}
elsif ( $backend eq 'ast-perl5' ) {
    require Data::Dumper;
    local $Data::Dumper::Terse    = 1;
    local $Data::Dumper::Sortkeys = 1;
    local $Data::Dumper::Indent   = 1;
    $result .=  Data::Dumper::Dumper( \@comp_unit );
}
elsif ( $backend eq 'ast-json' ) {
    require JSON;
    *UNIVERSAL::TO_JSON = sub {
        return { 'bless' => ref($_[0]), %{ $_[0] } };
    };
    $result .= JSON->new->allow_blessed->convert_blessed->encode( \@comp_unit ) . "\n";
}
else {
    die "it seems backend '$backend' is not supported";
}

if ( !$execute && !$compile_to_bin ) {
    print $result;
}

warn "done\n" if $verbose;

