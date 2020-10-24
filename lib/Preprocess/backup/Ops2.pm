#!/usr/bin/perl -I/home/phil/perl/cpan/DataTableText/lib
#-------------------------------------------------------------------------------
# Preprocess ▷ and ▶ as method dispatch operators in ANSI-C.
# Philip R Brenan at gmail dot com, Appa Apps Ltd Inc., 2020
#-------------------------------------------------------------------------------
# podDocumentation
package Preprocess::Ops;
our $VERSION = 20200831;
use warnings FATAL => qw(all);
use strict;
use Carp;
use Data::Dump qw(dump);
use Data::Table::Text qw(:all !trim);
use feature qw(say current_sub);
use utf8;

my $logFile = q(/home/phil/c/z/z/zzz.txt);                                      # Log to this file if present

#D1 Preprocess                                                                  # Preprocess ▷ and ▶ as method dispatch operators.

sub trim($)                                                                     #P Remove trailing white space and comment
 {my ($s) = @_;                                                                 # String
  $s =~ s(\s*//.*\n) ()r;
 }

sub method($)                                                                   #P Check whether a line of C code defines a method, returning (return, name, flags, comment) if it is, else ()
 {my ($line) = @_;                                                              # Line of C code
  return () if $line =~ m(test.*//T\S);                                         # Tests are never methods
  if ($line =~ m(\Astatic\s*(.*?)((?:\w|\$)+)\s+//(\w*)\s*(.*)\Z))              # Static function is always a method
   {return ($1, $2, $3, $4)
   }
  if ($line =~ m(\A(.*?)(new(?:\w|\$)+)\s+//(\w*)\s*(.*)\Z))                    # Constructor is always a method
#  {my @r = my ($return, $name, $flags, $comment) = ($1, $2, $3, $4);
#   return @r if $flags and $flags =~ m([C]);
   {return ($1, $2, $3, $4);
   }
  ()
  }

sub structure($)                                                                #P Check whether a line of C code defines a structure, returning (name, flags, comment) if it is, else ()
 {my ($line) = @_;                                                              # Line of C code

  if ($line =~ m(\A(typedef\s+)?struct\s+((?:\w|\$)+)\s*//(w*)\s*(.*)\Z))       # struct name, comment start, flags, comment
   {return ($2, $3, $4)
   }
  ()
  }

sub mapCode($)                                                                  # Find the structures and methods defined in a file
 {my ($file) = @_;                                                              # Input file

  my %methods;                                                                  # Method descriptions
  my %structures;                                                               # Structures defined

  my @code = readFile($file);                                                   # Read input file
  for my $line(@code)                                                           # Index of each line
   {next if $line =~ m(\A//);                                                   # Ignore comment lines

    my ($return, $name, $flags, $comment) = method($line);                      # Parse function return, name, description comment
    if ($name)
     {$methods{$name}++                                                         # Return type
     }
    else
     {my ($name, $flags, $comment) = structure($line);                          # Parse structure definition
      if ($name)
       {$structures{$name}++
       }
     }
   }

  genHash(q(PreprocessOpsMap),                                                  # Methods and structures in the C file being preprocessed
    methods    => \%methods,                                                    # Methods.
    structures => \%structures);                                                # Structure definitions.
 }

sub includeFile($$$$$)                                                          #P Expand include files so that we can pull in code and structures from other files in the includes folder.
 {my ($lineNumber, $inputFile, $cFile, $hFile, $code) = @_;                     # Line number of line being expanded, file containing line being expanded, output C file, output H file, line of code
  if ($code =~ m(\A(include)\s+))                                               # Parse preprocessor statement
   {my ($command, $relFile, @items) = split /\s+/, $code;
    my %items = map {$_=>1} @items;
    my $file = sumAbsAndRel($inputFile, $relFile);
    -e $file or confess "Cannot find include file: $file\n";

    my @code = readFile($file);
#   my $map  = mapCode($inputFile);

    my @c;
    for(my $i = 0; $i < @code; ++$i)                                            # Expand include files so that we can pull in code and structures from other files in the includes folder.
     {my  $c = $code[$i];                                                       # Replace $ with package name.
      if ($c =~ m(\Ainclude))                                                   # Expand include in included file
       {$c = &includeFile($i, $file, $cFile, $hFile, $c);
       }
      elsif ($c =~ m(\Aexports\s))                                              # Add exports from included package if named in the include list
       {my ($command, $name, @exports) = split m/\s+/, $c;                      # Export command, list name, exports in list
        if ($items{qq(:$name)})                                                 # Requested this list
         {for my $e(@exports)                                                    # Add exports unless they have been excluded
           {$items{$e} ++ unless $items{qq(!$e)};
           }
         }
       }
      elsif (method($c) or structure($c))                                       # Method or structure definition
       {if ($c =~ m((\S+)\s*//))                                                # Method or structure definition
         {my $item = $1;
          if ($command =~ m(include)      &&  $items            {$item})        # Include specifies the exact name of the thing we want
           {push @c, join ' ', "#line", $i+2, qq("$file"), "\n";
            for(; $i < @code; ++$i)
             {push @c, $code[$i];
              last if $code[$i] =~ m(\A })
             }
           }
         }
       }
     }
    my $l = $lineNumber + 2;
    return join '', @c, qq(#line $l "$inputFile"\n);
#   return join '', @c;
   }
  confess "Unable to parse include statement:\n$code";
 }

sub c($$$;$)                                                                    # Preprocess ▷ and ▶ as method dispatch operators in ANSI-C.
 {my ($inputFile, $cFile, $hFile, $column) = @_;                                # Input file, C output file, H output file, optional start column for comments (80)

  my $baseFile      = fn $inputFile;                                            # The base name of the file
  my $packageName   = ucfirst $baseFile;                                        # The package name which is used to replace $
  my $commentColumn = ($column // 80) - 1;                                      # Column in which to start comments

  my %methods;                                                                  # Method descriptions
  my %structures;                                                               # Structures defined
  my %structureParameters;                                                      # Structures used as parameters
  my %testsFound;                                                               # Tests found
  my %testsNeeded;                                                              # Tests needed
  my @forwards;                                                                 # Forward declarations of functions used as methods
  my @code = readFile($inputFile);                                              # Read code

  for my $i(keys @code)                                                         # Expand include files so that we can pull in code and structures from other files in the includes folder.
   {if ($code[$i] =~ m(\A(include)\s+))
     {$code[$i] = includeFile($i, $inputFile, $cFile, $hFile, $code[$i]);
     }
   }

  @code = map {"$_\n"} split /\n/, join '', @code;                              # Resplit code plus any additions into lines

  for my $c(@code)                                                              # Replace $ with package name.
   {$c =~ s(\$\$) ($baseFile)gs;                                                # $$ is base file name with first char lower cased
    $c =~ s(\$)   ($packageName)gs;                                             # $  is base file name with first character uppercased
   }

  if (1)                                                                        # Parse source code
   {my %duplicates; my @duplicates;                                             # Duplication check for first parameter plus short method name
    for my $i(keys @code)                                                       # Index of each line
     {my $line = $code[$i];
      next if $line =~ m(\A//);                                                 # Ignore comment lines

      my ($return, $name, $flags, $comment) = method($line);                    # Parse function return, name, description comment
      if ($name)
       {$methods{$name}{return}  = $return;                                     # Return type
        $methods{$name}{flags}   = {map {$_=>1} split //, $flags};              # Flags after comment start
        $methods{$name}{comment} = $comment;                                    # Comment
       ($methods{$name}{name})   = split /_/, $name;                            # Short name as used after call operator
        push @forwards, join ' ', trim($line);                                  # Save function definition for forward declaration

        for $i($i+1..$#code)                                                    # Parameter definitions
         {$line = $code[$i];
          if ($line =~ m(\A\s*[(]?(.*?)\s*(\w+)[,)]\s*//\s*(.*)\Z))             # Variable: Get type, parameter name, comment
           {push $methods{$name}{parameters}->@*, [$1, $2, $3];
           }
          elsif ($line =~ m(\A\s*(.*?)\s*\(\*(\s*(const)?\s*\w+)\)\s*(.*?)[,\)]\s*//\s*(.*)\Z)) # Function: Get type, parameter name, comment
           {push $methods{$name}{parameters}->@*, ["$1 (*$2) $4", $2, $5];
           }

          push @forwards, trim($line);                                          # Save function definition for forward declaration
          last if $line =~ m([\)]\s*//);                                        # End of parameter list
         }

        $forwards[-1] .= ';';                                                   # Terminate forward declaration
        if (my $o = $methods{$name}{structure} = $methods{$name}{parameters}[0][0])   # Structure parameter
         {$o =~ s((\A|\s+)const\s+) ();                                         # Remove const from structure name
          $structureParameters{$o}{$name}++;                                    # Record methods in each structure
          if (my $d = $duplicates{"$name$o"})                                   # Check for duplicate
           {push @duplicates, [$name, $o, $i, $d];                              # Record duplicate
           }
          $duplicates{"$name$o"} = $i;
         }
       }
      if (1)
       {my ($name, $flags, $comment) = structure($line);                        # Parse structure definition
        if ($name)
         {$structures{$name} = genHash(q(PreprocessOpsStruct),                  # Structure declaration
            name    => $name,                                                   # Name of structure
            flags   => $flags,                                                  # Flags for structure
            comment => $comment);                                               # Comment for structure
         }
       }
     }
    if (@duplicates)                                                            # Print duplicates
     {confess join "\n", "Duplicates:", dump(\@duplicates);
     }
    if (1)                                                                      # Locate tests for each method
     {my %m;                                                                    # Methods that need tests
      for my $m(sort keys %methods)
       {next if $methods{$m}{flags}{P};                                         # Ignore private methods marked with P
        $testsNeeded{$methods{$m}{name}}++;
       }

      for my $l(@code)                                                          # Each code line
       {my @t = $l =~ m((//T\w+))g;                                             # Tests located
        for my $t(@t)                                                           # Each test marker //T...
         {my $n = $t =~ s(\A//T) ()r;                                           # Remove //T
          delete $testsNeeded{$n};                                              # Test found for this method
          $testsFound{$n}++;                                                    # The tests we have found
         }
       }

      if (keys %testsNeeded)                                                    # Report methods that need tests
       {lll "The following methods need tests:\n", join "\n", sort keys %testsNeeded;
       }
     }
   }

#  if (! keys %methods)
#   {confess "No methods starting with static found in file: %inputFile";
#   }

  if (1)                                                                        # Write structureParameters
   {my @h;                                                                      # Generated code
    for my $s(sort keys %structureParameters)                                   # Each structure
     {next unless $structures{$s};                                              # The structure must be one defined in this file
      push @h, "struct ProtoTypes_$s {";                                        # Start structure
      for my $m(sort keys $structureParameters{$s}->%*)                         # Methods in structure
       {my $method = $methods{$m};                                              # Method
        my $s  = join '', '  ', $$method{return}, ' (*',  $$method{name}, ')('; # Start signature
        my $t  = join ' ', pad($s, $commentColumn), '//', $$method{comment};
        push @h, $t;
        my @p = $$method{parameters}->@*;                                       # Parameters for method
        for my $i(keys @p)                                                      # Each parameter
         {my ($return, $name, $comment) = $p[$i]->@*;

          my $cc      = $commentColumn;                                         # Comment column
          my $comma   = $i == $#p ? ');' : ',';                                 # Comma as separator
          my $Comment = "// $comment";                                          # Format comment
          my $off     = " " x 4;
          if ($return =~ m(\(*\s*(const)?\s*\w+\)))                             # Function parameter
           {push @h, join ' ', pad(qq($off$return$comma), $cc), $Comment;
           }
          else                                                                  # Variable parameter
           {push @h, join ' ', pad(qq($off$return $name$comma), $cc), $Comment;
           }
         }
       }
      push @h, join '', " } const ProtoTypes_", $s, ' =';
      push @h, join '', "{", join(', ', sort keys $structureParameters{$s}->%*), "};";
     }
    owf($hFile, join "\n", @forwards, @h, '');
   }

  if (1)                                                                        # Preprocess input C file
   {for my $c(@code)                                                            # Source code lines
     {$c =~ s{(\w+)\s*▶\s*(\w+)\s*\(} {$1->proto->$2($1, }gs;                   # Method call with arguments
      $c =~ s{(\w+)\s*▶\s*(\w+)}      {$1->proto->$2($1)}gs;                    # Method call with no arguments
      $c =~ s{(\w+)\s*▷\s*(\w+)\s*\(} {$1.proto->$2($1, }gs;                    # Method call with arguments
      $c =~ s{(\w+)\s*▷\s*(\w+)}      {$1.proto->$2($1)}gs;                     # Method call with no arguments

      $c =~ s{new(\w+\s*)\(([^:)]*:[^)]*)\)}                                    # Constructor with named arguments in parenthesis based on: https://gcc.gnu.org/onlinedocs/gcc-10.2.0/gcc/Designated-Inits.html#Designated-Inits
             {new$1(({struct $1 t = {$2, proto: &ProtoTypes_$1}; t;}))}gs;

      $c =~ s{new(\w+\s*)(\(\))?([,;])}                                         # Constructor followed by [,;] calls for default constructor.
             {new$1(({struct $1 t = {proto: &ProtoTypes_$1};   t;}))$3}gs;

      $c =~ s( +\Z) ()gs;                                                       # Remove trailing spaces at line ends
     }
    owf($cFile, qq(#line 1 "$inputFile"\n).join('', @code));                    # Output C file
#   owf($cFile, join '', @code);                                                # Output C file
   }

  genHash(q(PreprocessOpsParse),                                                # Structure of the C program being preprocessed
    methods             => \%methods,                                           # Methods.
    structures          => \%structures,                                        # Structure definitions.
    structureParameters => \%structureParameters,                               # Structures used as parameters
    testsFound          => \%testsFound,                                        # Tests found
    testsNeeded         => \%testsNeeded)                                       # Tests still needed
 }

#D0
#-------------------------------------------------------------------------------
# Export
#-------------------------------------------------------------------------------

use Exporter qw(import);

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

@ISA          = qw(Exporter);
@EXPORT_OK    = qw(
);
%EXPORT_TAGS  = (all=>[@EXPORT, @EXPORT_OK]);

# podDocumentation

=pod

=encoding utf-8

=head1 Name

Preprocess::Ops - Preprocess ▷ and ▶ as method dispatch operators in ANSI-C.

=head1 Synopsis

Preprocess ▷ and ▶ as method dispatch operators in ANSI-C by translating:

  p = node ▶ key("a");

to:

  p = node->proto->key(node, "a");

and:

  p = tree ▷ root;

to:

  p = tree.proto->root(tree);

Occurrences of the B<$> character are replaced by the base name of
the containing file with the first letter capitalized, so that

  typedef struct $Node $Node;

in a file called B<tree.c> becomes:

  typedef struct TreeNode TreeNode;

Occurrences of:

  newXXX

are replaced by:

  newXXX(({struct XXX t = {proto: &ProtoTypes_$1}; t;}))

Occurrences of:

  newXXX(a:1)

are replaced by:

  newXXX(({struct XXX t = {a:1, proto: &ProtoTypes_$1}; t;}))

The prototype vectors are generated by examining all the methods defined in the
B<c> file.  The prototype vectors are written to the specified B<h> file so
that they can be included in the B<c> file for use via the ▷ and ▶ operators.

See: L<https://github.com/philiprbrenan/C/blob/master/c/z/xml/xml.c> for a
working example.

=head1 Description

Preprocess ▷ and ▶ as method dispatch operators in ANSI-C.


Version 20200826.


The following sections describe the methods in each functional area of this
module.  For an alphabetic listing of all methods by name see L<Index|/Index>.



=head1 Preprocess

Preprocess ▷ and ▶ as method dispatch operators.

=head2 c($inputFile, $cFile, $hFile, $column)

Preprocess ▷ and ▶ as method dispatch operators in ANSI-C.

     Parameter   Description
  1  $inputFile  Input file
  2  $cFile      C output file
  3  $hFile      H output file
  4  $column     Optional start column for comments (80)

B<Example:>


    my $I   =     fpd($d, qw(includes));

    my $sbc = owf(fpe($d, qw(source base c)), <<'END');  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

  typedef struct $Node                                                            // Node definition
   {char * key;                                                                   // Key for the node
   } $Node;

  $Node new$Node                                                                  //C Create a new node
   (const struct $Node node)                                                      // Input key
   {return node;
   }

  static char * key_$Node                                                         // Get the key for a node
   (const $Node n)                                                                // Node to dump
   {return n.key;
   }

  static void dump_$Node                                                          // Dump a node
   (const $Node n)                                                                // Node to dump
   {printf("%s
", n ▷ key);
   }

  $Node n = new$Node(key: "a");                                                   //TnewNode
  assert(!strcmp(n ▷ key, "a"));
        n ▷ dump;                                                                 //Tdump
  END


    my $sdc = owf(fpe($d, qw(source derived c)), <<'END');  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

  typedef struct $Node                                                            // Node definition
   {wchar * key;
   } $Node;


  include base.c new$Node  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲


  include base.c key_$Node  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲


  include base.c dump_$Node  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

  END


    my $bc = fpe($I, qw(base c));  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    my $bh = fpe($I, qw(base h));

    my $dc = fpe($I, qw(derived c));  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

    my $dh = fpe($I, qw(derived h));


    my $r = c($sbc, $bc, $bh);                                                    # Preprocess base.c  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲


  # owf($logFile, readFile($bc)); exit;

    ok index(scalar(readFile($bc)), <<'END') > -1;                                # Generated base.c  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

  typedef struct BaseNode                                                            // Node definition
   {char * key;                                                                   // Key for the node
   } BaseNode;

  BaseNode newBaseNode                                                                  //C Create a new node
   (const struct BaseNode node)                                                      // Input key
   {return node;
   }

  static char * key_BaseNode                                                         // Get the key for a node
   (const BaseNode n)                                                                // Node to dump
   {return n.key;
   }

  static void dump_BaseNode                                                          // Dump a node
   (const BaseNode n)                                                                // Node to dump
   {printf("%s
", n.proto->key(n));
   }

  BaseNode n = newBaseNode(({struct BaseNode t = {key: "a", proto: &ProtoTypes_BaseNode}; t;}));                                                   //TnewNode
  assert(!strcmp(n.proto->key(n), "a"));
        n.proto->dump(n);                                                                 //Tdump
  END

  # owf($logFile, readFile($bh)); exit;
    is_deeply scalar(readFile($bh)), <<END;                                       # Generated base.h
  BaseNode newBaseNode
   (const struct BaseNode node);
  static char * key_BaseNode
   (const BaseNode n);
  static void dump_BaseNode
   (const BaseNode n);
  struct ProtoTypes_BaseNode {
    void  (*dump)(                                                                // Dump a node
      const BaseNode n);                                                          // Node to dump
    char *  (*key)(                                                               // Get the key for a node
      const BaseNode n);                                                          // Node to dump
   } const ProtoTypes_BaseNode =
  {dump_BaseNode, key_BaseNode};
  END



    my $R = c($sdc, $dc, $dh);                                                    # Preprocess derived.c  # 𝗘𝘅𝗮𝗺𝗽𝗹𝗲

  # owf($logFile, readFile($dc)); exit;
    ok index(scalar(readFile $dc), <<'END') > -1;
  static void dump_DerivedNode                                                          // Dump a node
   (const DerivedNode n)                                                                // Node to dump
   {printf("%s
", n.proto->key(n));
   }
  END
  # owf($logFile, readFile($dh)); exit;
    is_deeply scalar(readFile $dh), <<'END';
  DerivedNode newDerivedNode
   (const struct DerivedNode node);
  static char * key_DerivedNode
   (const DerivedNode n);
  static void dump_DerivedNode
   (const DerivedNode n);
  struct ProtoTypes_DerivedNode {
    void  (*dump)(                                                                // Dump a node
      const DerivedNode n);                                                       // Node to dump
    char *  (*key)(                                                               // Get the key for a node
      const DerivedNode n);                                                       // Node to dump
   } const ProtoTypes_DerivedNode =
  {dump_DerivedNode, key_DerivedNode};
  END

  # owf($logFile, dump(unbless $r)); exit;

    is_deeply $r,
  {
    methods             => {
                             dump_BaseNode => {
                                                comment    => "Dump a node",
                                                flags      => {},
                                                name       => "dump",
                                                parameters => [["const BaseNode", "n", "Node to dump"]],
                                                return     => "void ",
                                                structure  => "const BaseNode",
                                              },
                             key_BaseNode  => {
                                                comment    => "Get the key for a node",
                                                flags      => {},
                                                name       => "key",
                                                parameters => [["const BaseNode", "n", "Node to dump"]],
                                                return     => "char * ",
                                                structure  => "const BaseNode",
                                              },
                             newBaseNode   => {
                                                comment    => "Create a new node",
                                                flags      => { C => 1 },
                                                name       => "newBaseNode",
                                                parameters => [["const struct BaseNode", "node", "Input key"]],
                                                return     => "BaseNode ",
                                                structure  => "const struct BaseNode",
                                              },
                           },
    structureParameters => {
                             "BaseNode" => { dump_BaseNode => 1, key_BaseNode => 1 },
                             "struct BaseNode" => { newBaseNode => 1 },
                           },
    structures          => {
                             BaseNode => { comment => "Node definition", flags => "", name => "BaseNode" },
                           },
    testsFound          => { dump => 1, newNode => 1 },
    testsNeeded         => { key => 1, newBaseNode => 1 },
  };

  # owf($logFile, dump(unbless $R)); exit;

    is_deeply $R,
  {
    methods             => {
                             dump_DerivedNode => {
                                                   comment    => "Dump a node",
                                                   flags      => {},
                                                   name       => "dump",
                                                   parameters => [["const DerivedNode", "n", "Node to dump"]],
                                                   return     => "void ",
                                                   structure  => "const DerivedNode",
                                                 },
                             key_DerivedNode  => {
                                                   comment    => "Get the key for a node",
                                                   flags      => {},
                                                   name       => "key",
                                                   parameters => [["const DerivedNode", "n", "Node to dump"]],
                                                   return     => "char * ",
                                                   structure  => "const DerivedNode",
                                                 },
                             newDerivedNode   => {
                                                   comment    => "Create a new node",
                                                   flags      => { C => 1 },
                                                   name       => "newDerivedNode",
                                                   parameters => [["const struct DerivedNode", "node", "Input key"]],
                                                   return     => "DerivedNode ",
                                                   structure  => "const struct DerivedNode",
                                                 },
                           },
    structureParameters => {
                             "DerivedNode"        => { dump_DerivedNode => 1, key_DerivedNode => 1 },
                             "struct DerivedNode" => { newDerivedNode => 1 },
                           },
    structures          => {
                             DerivedNode => { comment => "Node definition", flags => "", name => "DerivedNode" },
                           },
    testsFound          => {},
    testsNeeded         => { dump => 1, key => 1, newDerivedNode => 1 },
  };



=head2 PreprocessOpsParse Definition


Structure of the C program being preprocessed




=head3 Output fields


=head4 methods

Methods.

=head4 structureParameters

Structures used as parameters

=head4 structures

Structure definitions.

=head4 testsFound

Tests found

=head4 testsNeeded

Tests still needed



=head2 PreprocessOpsStruct Definition


Structure declaration




=head3 Output fields


=head4 comment

Comment for structure

=head4 flags

Flags for structure

=head4 methods

Methods.

=head4 name

Name of structure

=head4 structureParameters

Structures used as parameters

=head4 structures

Structure definitions.

=head4 testsFound

Tests found

=head4 testsNeeded

Tests still needed



=head1 Private Methods

=head2 trim($s)

Remove trailing white space and comment

     Parameter  Description
  1  $s         String

=head2 method($line)

Check whether a line of C code defines a method, returning (return, name, flags, comment) if it is, else ()

     Parameter  Description
  1  $line      Line of C code

=head2 structure($line)

Check whether a line of C code defines a structure, returning (name, flags, comment) if it is, else ()

     Parameter  Description
  1  $line      Line of C code

=head2 includeFile($lineNumber, $inputFile, $cFile, $hFile, $code)

Expand include files so that we can pull in code and structures from other files in the includes folder.

     Parameter    Description
  1  $lineNumber  Line number of line being expanded
  2  $inputFile   File containing line being expanded
  3  $cFile       Output C file
  4  $hFile       Output H file
  5  $code        Line of code


=head1 Index


1 L<c|/c> - Preprocess ▷ and ▶ as method dispatch operators in ANSI-C.

2 L<includeFile|/includeFile> - Expand include files so that we can pull in code and structures from other files in the includes folder.

3 L<method|/method> - Check whether a line of C code defines a method, returning (return, name, flags, comment) if it is, else ()

4 L<structure|/structure> - Check whether a line of C code defines a structure, returning (name, flags, comment) if it is, else ()

5 L<trim|/trim> - Remove trailing white space and comment

=head1 Installation

This module is written in 100% Pure Perl and, thus, it is easy to read,
comprehend, use, modify and install via B<cpan>:

  sudo cpan install Preprocess::Ops

=head1 Author

L<philiprbrenan@gmail.com|mailto:philiprbrenan@gmail.com>

L<http://www.appaapps.com|http://www.appaapps.com>

=head1 Copyright

Copyright (c) 2016-2019 Philip R Brenan.

This module is free software. It may be used, redistributed and/or modified
under the same terms as Perl itself.

=cut



# Tests and documentation

sub test
 {my $p = __PACKAGE__;
  binmode($_, ":utf8") for *STDOUT, *STDERR;
  return if eval "eof(${p}::DATA)";
  my $s = eval "join('', <${p}::DATA>)";
  $@ and die $@;
  eval $s;
  $@ and die $@;
  1
 }

test unless caller;

1;
# podDocumentation
__DATA__
use warnings FATAL=>qw(all);
use strict;
require v5.26;
use Time::HiRes qw(time);
use Test::More tests => 6;

my $startTime = time();
my $localTest = ((caller(1))[0]//'Preprocess::Ops') eq "Preprocess::Ops";       # Local testing mode
Test::More->builder->output("/dev/null") if $localTest;                         # Suppress output in local testing mode
makeDieConfess;

my $d = temporaryFolder;

  if (1) {                                                                      #Tc
  my $I   =     fpd($d, qw(includes));
  my $sbc = owf(fpe($d, qw(source base c)), <<'END');
typedef struct $Node                                                            // Node definition
 {char * key;                                                                   // Key for the node
 } $Node;

$Node new$Node                                                                  //C Create a new node
 (const struct $Node node)                                                      // Input key
 {return node;
 }

static char * key_$Node                                                         // Get the key for a node
 (const $Node n)                                                                // Node to dump
 {return n.key;
 }

static void dump_$Node                                                          // Dump a node
 (const $Node n)                                                                // Node to dump
 {printf("%s\n", n ▷ key);
 }

$Node n = new$Node(key: "a");                                                   //TnewNode
assert(!strcmp(n ▷ key, "a"));
      n ▷ dump;                                                                 //Tdump
END

  my $sdc = owf(fpe($d, qw(source derived c)), <<'END');
typedef struct $Node                                                            // Node definition
 {wchar * key;
 } $Node;

include base.c new$Node
include base.c key_$Node
include base.c dump_$Node
END

  my $bc = fpe($I, qw(base c));
  my $bh = fpe($I, qw(base h));
  my $dc = fpe($I, qw(derived c));
  my $dh = fpe($I, qw(derived h));

  my $r = c($sbc, $bc, $bh);                                                    # Preprocess base.c

# owf($logFile, readFile($bc)); exit;
  ok index(scalar(readFile($bc)), <<'END') > -1;                                # Generated base.c
typedef struct BaseNode                                                            // Node definition
 {char * key;                                                                   // Key for the node
 } BaseNode;

BaseNode newBaseNode                                                                  //C Create a new node
 (const struct BaseNode node)                                                      // Input key
 {return node;
 }

static char * key_BaseNode                                                         // Get the key for a node
 (const BaseNode n)                                                                // Node to dump
 {return n.key;
 }

static void dump_BaseNode                                                          // Dump a node
 (const BaseNode n)                                                                // Node to dump
 {printf("%s\n", n.proto->key(n));
 }

BaseNode n = newBaseNode(({struct BaseNode t = {key: "a", proto: &ProtoTypes_BaseNode}; t;}));                                                   //TnewNode
assert(!strcmp(n.proto->key(n), "a"));
      n.proto->dump(n);                                                                 //Tdump
END

# owf($logFile, readFile($bh)); exit;
  is_deeply scalar(readFile($bh)), <<END;                                       # Generated base.h
BaseNode newBaseNode
 (const struct BaseNode node);
static char * key_BaseNode
 (const BaseNode n);
static void dump_BaseNode
 (const BaseNode n);
struct ProtoTypes_BaseNode {
  void  (*dump)(                                                                // Dump a node
    const BaseNode n);                                                          // Node to dump
  char *  (*key)(                                                               // Get the key for a node
    const BaseNode n);                                                          // Node to dump
 } const ProtoTypes_BaseNode =
{dump_BaseNode, key_BaseNode};
END


  my $R = c($sdc, $dc, $dh);                                                    # Preprocess derived.c
# owf($logFile, readFile($dc)); exit;
  ok index(scalar(readFile $dc), <<'END') > -1;
static void dump_DerivedNode                                                          // Dump a node
 (const DerivedNode n)                                                                // Node to dump
 {printf("%s\n", n.proto->key(n));
 }
END
# owf($logFile, readFile($dh)); exit;
  is_deeply scalar(readFile $dh), <<'END';
DerivedNode newDerivedNode
 (const struct DerivedNode node);
static char * key_DerivedNode
 (const DerivedNode n);
static void dump_DerivedNode
 (const DerivedNode n);
struct ProtoTypes_DerivedNode {
  void  (*dump)(                                                                // Dump a node
    const DerivedNode n);                                                       // Node to dump
  char *  (*key)(                                                               // Get the key for a node
    const DerivedNode n);                                                       // Node to dump
 } const ProtoTypes_DerivedNode =
{dump_DerivedNode, key_DerivedNode};
END

# owf($logFile, dump(unbless $r)); exit;

  is_deeply $r,
{
  methods             => {
                           dump_BaseNode => {
                                              comment    => "Dump a node",
                                              flags      => {},
                                              name       => "dump",
                                              parameters => [["const BaseNode", "n", "Node to dump"]],
                                              return     => "void ",
                                              structure  => "const BaseNode",
                                            },
                           key_BaseNode  => {
                                              comment    => "Get the key for a node",
                                              flags      => {},
                                              name       => "key",
                                              parameters => [["const BaseNode", "n", "Node to dump"]],
                                              return     => "char * ",
                                              structure  => "const BaseNode",
                                            },
                           newBaseNode   => {
                                              comment    => "Create a new node",
                                              flags      => { C => 1 },
                                              name       => "newBaseNode",
                                              parameters => [["const struct BaseNode", "node", "Input key"]],
                                              return     => "BaseNode ",
                                              structure  => "const struct BaseNode",
                                            },
                         },
  structureParameters => {
                           "BaseNode" => { dump_BaseNode => 1, key_BaseNode => 1 },
                           "struct BaseNode" => { newBaseNode => 1 },
                         },
  structures          => {
                           BaseNode => { comment => "Node definition", flags => "", name => "BaseNode" },
                         },
  testsFound          => { dump => 1, newNode => 1 },
  testsNeeded         => { key => 1, newBaseNode => 1 },
};

# owf($logFile, dump(unbless $R)); exit;

  is_deeply $R,
{
  methods             => {
                           dump_DerivedNode => {
                                                 comment    => "Dump a node",
                                                 flags      => {},
                                                 name       => "dump",
                                                 parameters => [["const DerivedNode", "n", "Node to dump"]],
                                                 return     => "void ",
                                                 structure  => "const DerivedNode",
                                               },
                           key_DerivedNode  => {
                                                 comment    => "Get the key for a node",
                                                 flags      => {},
                                                 name       => "key",
                                                 parameters => [["const DerivedNode", "n", "Node to dump"]],
                                                 return     => "char * ",
                                                 structure  => "const DerivedNode",
                                               },
                           newDerivedNode   => {
                                                 comment    => "Create a new node",
                                                 flags      => { C => 1 },
                                                 name       => "newDerivedNode",
                                                 parameters => [["const struct DerivedNode", "node", "Input key"]],
                                                 return     => "DerivedNode ",
                                                 structure  => "const struct DerivedNode",
                                               },
                         },
  structureParameters => {
                           "DerivedNode"        => { dump_DerivedNode => 1, key_DerivedNode => 1 },
                           "struct DerivedNode" => { newDerivedNode => 1 },
                         },
  structures          => {
                           DerivedNode => { comment => "Node definition", flags => "", name => "DerivedNode" },
                         },
  testsFound          => {},
  testsNeeded         => { dump => 1, key => 1, newDerivedNode => 1 },
};
   }

clearFolder($d, 10);

done_testing;

if ($localTest)
 {say "TO finished in ", (time() - $startTime), " seconds";
 }

1;
