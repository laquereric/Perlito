use v6;

class Python {
    sub tab($level) { "    " x $level }
}

class CompUnit {
    has $.name;
    has %.attributes;
    has %.methods;
    has @.body;
    method emit { $self.emit_indented(0) }
    method emit_indented( $level ) {
        Python::tab($level) ~ 'class ' ~ $.name ~ ":\n" ~ 
            (@.body.>>emit_indented($level + 1)).join( "\n" ) ~ "\n"
    }
}

class Val::Int {
    has $.int;
    method emit { $.int }
    method emit_indented( $level ) {
        Python::tab($level) ~ $.int 
    }
}

class Val::Bit {
    has $.bit;
    method emit { $.bit }
    method emit_indented( $level ) {
        Python::tab($level) ~ $.bit 
    }
}

class Val::Num {
    has $.num;
    method emit { $.num }
    method emit_indented( $level ) {
        Python::tab($level) ~ $.num 
    }
}

class Val::Buf {
    has $.buf;
    method emit { $self.emit_indented(0) }
    method emit_indented( $level ) {
        Python::tab($level) ~ '"""' ~ $.buf ~ '"""' 
    }
}

class Val::Undef {
    method emit { 'None' }
    method emit_indented( $level ) {
        Python::tab($level) ~ 'None' 
    }
}

class Val::Object {
    has $.class;
    has %.fields;
    method emit { $self.emit_indented(0) }
    method emit_indented( $level ) {
        Python::tab($level) ~ 
            $.class.perl ~ '(' ~ %.fields.perl ~ ')';
    }
}

class Lit::Array {
    has @.array1;
    method emit { $self.emit_indented(0) }
    method emit_indented( $level ) {
        Python::tab($level) ~ 
            '[' ~ (@.array1.>>emit).join(', ') ~ ']';
    }
}

class Lit::Hash {
    has @.hash1;
    method emit { $self.emit_indented(0) }
    method emit_indented( $level ) {
        my $fields = @.hash1;
        my @dict;
        for @$fields -> $field { 
            push @dict, (($field[0]).emit ~ ':' ~ ($field[1]).emit);
        }; 
        Python::tab($level) ~ 
            '{' ~ @dict.join(', ') ~ '}';
    }
}

class Lit::Code {
    # XXX
    1;
}

class Lit::Object {
    has $.class;
    has @.fields;
    method emit { $self.emit_indented(0) }
    method emit_indented( $level ) {
        my $fields = @.fields;
        my $str = '';
        for @$fields -> $field { 
            $str = $str ~ ($field[0]).emit ~ ' = ' ~ ($field[1]).emit ~ ',';
        }; 
        Python::tab($level) ~ 
            $.class ~ '( ' ~ $str ~ ' )';
    }
}

class Index {
    has $.obj;
    has $.index_exp;
    method emit { $self.emit_indented(0) }
    method emit_indented( $level ) {
        Python::tab($level) ~ 
            $.obj.emit ~ '[' ~ $.index_exp.emit ~ ']';
    }
}

class Lookup {
    has $.obj;
    has $.index_exp;
    method emit { $self.emit_indented(0) }
    method emit_indented( $level ) {
        Python::tab($level) ~ 
            $.obj.emit ~ '[' ~ $.index_exp.emit ~ ']';
    }
}

class Var {
    has $.sigil;
    has $.twigil;
    has $.name;
    method emit { $self.emit_indented(0) }
    method emit_indented( $level ) {
        # Normalize the sigil here into $
        # $x    => $x
        # @x    => $List_x
        # %x    => $Hash_x
        # &x    => $Code_x
        my $table = {
            '$' => 'scalar_',
            '@' => 'List_',
            '%' => 'Hash_',
            '&' => 'Code_',
        };
        return Python::tab($level) ~ (
               ( $.twigil eq '.' )
            ?? ( 'self.' ~ $.name )
            !!  (    ( $.name eq '/' )
                ??   ( $table{$.sigil} ~ 'MATCH' )
                !!   ( $table{$.sigil} ~ $.name )
                )
            )
    };
    method name {
        $.name
    };
}

class Bind {
    has $.parameters;
    has $.arguments;
    method emit {
        if $.parameters.isa( 'Lit::Array' ) {
            
            #  [$a, [$b, $c]] = [1, [2, 3]]
            
            my $a = $.parameters.array;
            #my $b = $.arguments.array;
            my $str = "if True:\n# {\n ";
            my $i = 0;
            for @$a -> $var { 
                my $bind = Bind.new( 
                    parameters => $var, 
                    # arguments => ($b[$i]) );
                    arguments  => Index.new(
                        obj    => $.arguments,
                        index  => Val::Int.new( int => $i )
                    )
                );
                $str = $str ~ ' ' ~ $bind.emit ~ "\n";
                $i = $i + 1;
            };
            return $str ~ $.parameters.emit ~ "\n# }\n";
        };
        if $.parameters.isa( 'Lit::Hash' ) {

            #  {:$a, :$b} = { a => 1, b => [2, 3]}

            my $a = $.parameters.hash;
            my $b = $.arguments.hash;
            my $str = "if 1:\n#{\n";
            my $i = 0;
            my $arg;
            for @$a -> $var {

                $arg = Val::Undef.new();
                for @$b -> $var2 {
                    #say "COMPARE ", ($var2[0]).buf, ' eq ', ($var[0]).buf;
                    if ($var2[0]).buf eq ($var[0]).buf {
                        $arg = $var2[1];
                    }
                };

                my $bind = Bind.new( parameters => $var[1], arguments => $arg );
                $str = $str ~ ' ' ~ $bind.emit ~ "\n";
                $i = $i + 1;
            };
            return $str ~ $.parameters.emit ~ "\n# }\n";
        };

        if $.parameters.isa( 'Lit::Object' ) {

            #  Obj.new(:$a, :$b) = $obj

            my $class = $.parameters.class;
            my $a     = $.parameters.fields;
            my $b     = $.arguments;
            my $str   = 'do { ';
            my $str   = "if 1:\n# {\n";
            my $i     = 0;
            my $arg;
            for @$a -> $var {
                my $bind = Bind.new( 
                    parameters => $var[1], 
                    arguments  => Call.new( invocant => $b, method => ($var[0]).buf, arguments => [ ], hyper => 0 )
                );
                $str = $str ~ ' ' ~ $bind.emit ~ "\n";
                $i = $i + 1;
            };
            return $str ~ $.parameters.emit ~ "\n# }\n";
        };
    
        $.parameters.emit ~ ' = ' ~ $.arguments.emit;
    }
}

class Proto {
    has $.name;
    method emit {
        ~$.name        
    }
}

class Call {
    has $.invocant;
    has $.hyper;
    has $.method;
    has @.arguments;
    #has $.hyper;
    method emit {
    # XXX
        my $invocant = $.invocant.emit;
        if     ($.method eq 'perl')
            || ($.method eq 'yaml')
            || ($.method eq 'say' )
            || ($.method eq 'join')
            || ($.method eq 'chars')
            || ($.method eq 'isa')
        { 
            if ($.hyper) {
            	return "map(lambda: Main." ~ $.method ~ "( self, " ~ (@.arguments.>>emit).join(', ') ~ ') , ' ~ $invocant ~ ")\n";
            }
            else {
                return "Main." ~ $.method ~ '(' ~ $invocant ~ ', ' ~ (@.arguments.>>emit).join(', ') ~ ')';
            }
        };

        my $meth = $.method;
        if  $meth eq 'postcircumfix:<( )>'  {
             $meth = '';  
        };
        
        my $call = '->' ~ $meth ~ '(' ~ (@.arguments.>>emit).join(', ') ~ ')';
        if ($.hyper) {
        #CT
            '[ map { $_' ~ $call ~ ' } @{ ' ~ $invocant ~ ' } ]';
        }
        else {
            $invocant ~ $call;
        };

    }
}

class Apply {
    has $.code;
    has @.arguments;
    method emit {
        
        my $code = $.code;

        if $code.isa( 'Str' ) { }
        else {
            return '(' ~ $.code.emit ~ ').(' ~ (@.arguments.>>emit).join(', ') ~ ')';
        };

        if $code eq 'self'       { return 'self' };

        if $code eq 'say'        { return 'Main::say('   ~ (@.arguments.>>emit).join(', ') ~ ')' };
        if $code eq 'print'      { return 'print(' ~ (@.arguments.>>emit).join(', ') ~ ')' };
        if $code eq 'warn'       { return 'warn('        ~ (@.arguments.>>emit).join(', ') ~ ')' };

        if $code eq 'array'      { return '[' ~ (@.arguments.>>emit).join(' ')    ~ ']' };

        if $code eq 'prefix:<~>' { return '("" . ' ~ (@.arguments.>>emit).join(' ') ~ ')' };
        if $code eq 'prefix:<!>' { return '('  ~ (@.arguments.>>emit).join(' ')    ~ ' ? 0 : 1)' };
        if $code eq 'prefix:<?>' { return '('  ~ (@.arguments.>>emit).join(' ')    ~ ' ? 1 : 0)' };

        if $code eq 'prefix:<$>' { return '${' ~ (@.arguments.>>emit).join(' ')    ~ '}' };
        if $code eq 'prefix:<@>' { return '@{' ~ (@.arguments.>>emit).join(' ')    ~ '}' };
        if $code eq 'prefix:<%>' { return '%{' ~ (@.arguments.>>emit).join(' ')    ~ '}' };

        if $code eq 'infix:<~>'  { return '('  ~ (@.arguments.>>emit).join(' . ')  ~ ')' };
        if $code eq 'infix:<+>'  { return '('  ~ (@.arguments.>>emit).join(' + ')  ~ ')' };
        if $code eq 'infix:<->'  { return '('  ~ (@.arguments.>>emit).join(' - ')  ~ ')' };
        
        if $code eq 'infix:<&&>' { return '('  ~ (@.arguments.>>emit).join(' && ') ~ ')' };
        if $code eq 'infix:<||>' { return '('  ~ (@.arguments.>>emit).join(' || ') ~ ')' };
        if $code eq 'infix:<eq>' { return '('  ~ (@.arguments.>>emit).join(' eq ') ~ ')' };
        if $code eq 'infix:<ne>' { return '('  ~ (@.arguments.>>emit).join(' ne ') ~ ')' };
 
        if $code eq 'infix:<==>' { return '('  ~ (@.arguments.>>emit).join(' == ') ~ ')' };
        if $code eq 'infix:<!=>' { return '('  ~ (@.arguments.>>emit).join(' != ') ~ ')' };

        if $code eq 'ternary:<?? !!>' { 
            return '(' ~ (@.arguments[0]).emit ~
                 ' ? ' ~ (@.arguments[1]).emit ~
                 ' : ' ~ (@.arguments[2]).emit ~
                  ')' };
        
        $.code ~ '(' ~ (@.arguments.>>emit).join(', ') ~ ')';
        # '(' ~ $.code.emit ~ ')->(' ~ @.arguments.>>emit.join(', ') ~ ')';
    }
    method emit_indented( $level ) {
        Python::tab($level) ~ $self.emit 
    }
}

class Return {
    has $.result;
    method emit {
        return
        #'do { print Main::perl(caller(),' ~ $.result.emit ~ '); return(' ~ $.result.emit ~ ') }';
        'return ' ~ $.result.emit ~ "\n";
    }
}

class If {
    has $.cond;
    has @.body;
    has @.otherwise;
    method emit {
        'do { if (' ~ $.cond.emit ~ ') { ' ~ (@.body.>>emit).join(';') ~ ' } else { ' ~ (@.otherwise.>>emit).join(';') ~ ' } }';
    }
}

class For {
    has $.cond;
    has @.body;
    has @.topic;
    method emit {
        my $cond = $.cond;
        if   $cond.isa( 'Var' ) 
          && $cond.sigil eq '@' 
        {
            $cond = Apply.new( code => 'prefix:<@>', arguments => [ $cond ] );
        };
        'do { for my ' ~ $.topic.emit ~ ' ( ' ~ $cond.emit ~ ' ) { ' ~ (@.body.>>emit).join(';') ~ ' } }';
    }
}

class Decl {
    has $.decl;
    has $.type;
    has $.var;
    method emit {
        my $decl = $.decl;
        my $name = $.var.name;
           ( $decl eq 'has' )
        ?? ( 'sub ' ~ $name ~ ' { ' ~
            '@_ == 1 ' ~
                '? ( $_[0]->{' ~ $name ~ '} ) ' ~
                ': ( $_[0]->{' ~ $name ~ '} = $_[1] ) ' ~
            '}' )
        !! $.decl ~ ' ' ~ $.type ~ ' ' ~ $.var.emit;
    }
}

class Sig {
    has $.invocant;
    has $.positional;
    has $.named;
    method emit {
        ' print \'Signature - TODO\'; die \'Signature - TODO\'; '
    };
    method invocant {
        $.invocant
    };
    method positional {
        $.positional
    }
}

class Method {
    has $.name;
    has $.sig;
    has @.block;
    method emit {
        # TODO - signature binding
        my $sig = $.sig;
        # say "Sig: ", $sig.perl;
        my $invocant = $sig.invocant; 
        # say $invocant.emit;

        my $pos = $sig.positional;
        my $str = 'my $List__ = \@_; ';   # no strict "vars"; ';

        # TODO - follow recursively
        my $pos = $sig.positional;
        for @$pos -> $field { 
            if ( $field.isa('Lit::Array') ) {
                $str = $str ~ 'my (' ~ (($field.array).>>emit).join(', ') ~ '); ';
            }
            else {
                $str = $str ~ 'my ' ~ $field.emit ~ '; ';
            };
        };

        my $bind = Bind.new( 
            parameters => Lit::Array.new( array => $sig.positional ), 
            arguments  => Var.new( sigil => '@', twigil => '', name => '_' )
        );
        $str = $str ~ $bind.emit ~ '; ';

#        my $pos = $sig.positional;
#        my $str = '';
#        my $i = 1;
#        for @$pos -> $field { 
#            $str = $str ~ 'my ' ~ $field.emit ~ ' = $_[' ~ $i ~ ']; ';
#            $i = $i + 1;
#        };

        'sub ' ~ $.name ~ ' { ' ~ 
          'my ' ~ $invocant.emit ~ ' = shift; ' ~
          $str ~
          (@.block.>>emit).join('; ') ~ 
        ' }'
    }
}

class Sub {
    has $.name;
    has $.sig;
    has @.block;
    method emit {
        # TODO - signature binding
        my $sig = $.sig;
        # say "Sig: ", $sig.perl;
        ## my $invocant = $sig.invocant; 
        # say $invocant.emit;
        my $pos = $sig.positional;
        my $str = 'my $List__ = \@_; ';  # no strict "vars"; ';

        # TODO - follow recursively
        my $pos = $sig.positional;
        for @$pos -> $field { 
            if ( $field.isa('Lit::Array') ) {
                $str = $str ~ 'my (' ~ (($field.array).>>emit).join(', ') ~ '); ';
            }
            else {
                $str = $str ~ 'my ' ~ $field.emit ~ '; ';
            };
            #$str = $str ~ 'my ' ~ $field.emit ~ '; ';
        };

        my $bind = Bind.new( 
            parameters => Lit::Array.new( array => $sig.positional ), 
            arguments  => Var.new( sigil => '@', twigil => '', name => '_' )
        );
        $str = $str ~ $bind.emit ~ '; ';

#        my $i = 0;
#        for @$pos -> $field { 
#            my $bind = Bind.new( 
#                parameters => $field, 
#                arguments  => Index.new(
#                        obj    => Var.new( sigil => '@', twigil => '', name => '_' ),
#                        index  => Val::Int.new( int => $i )
#                    ),
#                );
#            $str = $str ~ $bind.emit ~ '; ';
#            $i = $i + 1;
#        };
        'sub ' ~ $.name ~ ' { ' ~ 
          ## 'my ' ~ $invocant.emit ~ ' = $_[0]; ' ~
          $str ~
          (@.block.>>emit).join('; ') ~ 
        ' }'
    }
}

class Do {
    has @.block;
    method emit {
    	"if 1:\n# {\n" ~
    	(@.block.>>emit).join("\n") ~
    	"\n# }\n"
    }
}

class Use {
    has $.mod;
    method emit {
        'from ' ~ $.mod ~ 'import *'
    }
}

