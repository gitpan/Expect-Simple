package Expect::Simple;

use strict;
use warnings;

use Carp;
use Expect;

our $VERSION = '0.03';


sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $obj  = {
	      Timeout => 1000,
	      Debug => 0,
	      Verbose => 0,
	      Prompt => undef,
	      DisconnectCmd => undef,
	      Cmd => undef,
	      RawPty => 0,
	     };

  bless ($obj, $class);

  my $attr = shift or
    croak( __PACKAGE__, ': must specify some attributes!\n' );

  while( my ( $attr, $val ) = each %{$attr} )
  {
    croak( __PACKAGE__, ": attribute error : `$attr' is not recognized \n" )
      unless exists $obj->{$attr};

    $obj->{$attr} = $val;
  }


  # ensure all the attribures are set
  foreach ( keys %$obj )
  {
    croak( __PACKAGE__, ": must specify attribute `$_'\n" )
      unless defined $obj->{$_};
  }

  # rework prompt
  $obj->{Prompt} = [ 'ARRAY' eq ref $obj->{Prompt} ?
		   @{$obj->{Prompt}} : $obj->{Prompt} ];


  eval { $obj->_connect; };

  croak (__PACKAGE__, ': ', $@) if $@;

  return $obj;
}

# _connect - start up the cmd
#
# creates an Expect object which talks to the specified command.  It dies with
# an appropriate message upon error.

sub _connect
{
  my $obj = shift;

  print STDERR "Running command..."
    if $obj->{Verbose};

  $obj->{_conn} = Expect->new();

  $obj->{_conn}->raw_pty(1) if $obj->{RawPty};

  $obj->{_conn}->spawn( 'ARRAY' eq ref($obj->{Cmd})
			? @{$obj->{Cmd}}
			:   $obj->{Cmd} )
    or croak( __PACKAGE__, ": error spawning command\n" );

  print STDERR "done.\n"
    if $obj->{Verbose};

  $obj->{_conn}->debug( $obj->{Debug} );

  $obj->{_conn}->log_stdout( $obj->{Verbose} > 3 ? 1 : 0 );

  $obj->_expect( @{$obj->{Prompt}} ) 
    or croak( __PACKAGE__, ": couldn't find prompt\n");
}

sub _disconnect
{
  my $obj = shift;

  return unless $obj->{_conn};

  print STDERR "Disconnecting.\n"
    if $obj->{Verbose};

  $obj->{_conn}->print( $obj->{DisconnectCmd}, "\n" );
  $obj->_expect( 'the unexpected' );
  croak( __PACKAGE__, ": disconnection error\n" )
    unless $obj->{_conn}->exp_error =~ /^(2|3)/;

  $obj->{_conn} = undef;
}


# send( @commands )
#
# send commands to the server. each command is sent independently.
# it waits for the  prompt to indicate success.
#
# it croaks if there was an error.  $obj->error returns
# the results of the communication to
# the server which caused the error.

sub send
{
  my $obj = shift;

  foreach ( @_ )
  {
    print STDERR "Sending `$_'\n"
      if $obj->{Verbose} && ! $obj->{_conn}->log_stdout;
    $obj->{_conn}->print( $_, "\n");

    $obj->_expect( @{$obj->{Prompt}} ) || 
      croak( __PACKAGE__, ": couldn't find prompt after send\n");
  }
}


# _expect( @match_patterns )
#
# match output of the server.The error message is massaged to
# make it more obvious.
#
# it returns 1 upon success, undef if there was an error.

sub _expect
{
  my $obj = shift;

  my $match = $obj->{_conn}->expect( $obj->{Timeout}, @_ ); 

  $obj->{_error} = undef;

  unless ( defined $match )
  {
    local $_ = $obj->{_conn}->exp_error;

    if ( /^1/ )
    {
      $obj->{_error} = 'connection timed out';
    }
    elsif ( /^(2|3)/ )
    {
      $obj->{_error} = 'connection unexpectedly terminated';
    }
    else
    {
      my ( $errno, $errmsg) = /(\d):(.*)/;
    
      $obj->{_error} = "error in communications: $errmsg";
    }

    return undef;
  }

  1;
}

sub error { shift()->{_error} }
sub error_expect { shift()->{_conn}->exp_error }
sub match_idx { shift()->{_conn}->exp_match_number }
sub match_str { shift()->{_conn}->exp_match }
sub before { shift()->{_conn}->exp_before }
sub after { shift()->{_conn}->exp_after }

sub expect_handle{ shift()->{_conn} }

sub DESTROY { shift()->_disconnect }


# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__

=head1 NAME

Expect::Simple - wrapper around the Expect module

=head1 SYNOPSIS

  use Expect::Simple;

  my $obj = new Expect::Simple 
        { Cmd => [ dmcoords => 'verbose=1', "infile=$infile"],
	  Prompt => [ -re => 'dmcoords>:\s+' ],
	  DisconnectCmd => 'q',
	  Verbose => 0,
	  Debug => 0,
	  Timeout => 100
	};

  $obj->send( $cmd );
  print $obj->before;
  print $obj->after;
  print $obj->match_str, "\n";
  print $obj->match_idx, "\n";
  print $obj->error_expect;
  print $obj->error;

  $expect_object = $obj->expect_handle;

=head1 DESCRIPTION

C<Expect::Simple> is a wrapper around the C<Expect> module which
should suffice for simple applications.  It hides most of the
C<Expect> machinery; the C<Expect> object is available for tweaking if
need be.

Generally, one starts by creating an B<Expect::Simple> object using
B<new>.  This will start up the target program, and will wait until
one of the specified prompts is output by the target.  At that point
the caller should B<send()> commands to the program; the results are
available via the B<before>, B<after>, B<match_str>, and B<match_idx>
methods.  Since B<Expect> simulates a terminal, there will be extra
C<\r> characters at the end of each line in the result (on UNIX at
least).  This is easily fixed:

    ($res = $obj->before) =~ tr/\r//d;
    @lines = split( "\n", $res );

This is B<not> done automatically.


Exceptions will be thrown on error (match with C</Expect::Simple/>).
Errors from B<Expect> are available via the B<error_expect> method.
More human readable errors are available via the B<error> method.

The connection is automatically broken (by sending the specified
disconnect command to the target) when the B<Expect::Simple> object is 
destroyed.


=head2 Methods

=over 8

=item new

    $obj = Expect::Simple->new( \%attr );

This creates a new object, starting up the program with which to
communicate (using the B<Expect> B<spawn> method) and waiting for a
prompt.  The passed hash reference must contain at least the
B<Prompt>, B<DisconnectCmd>, and B<Cmd> elements.  The available
attributes are:

=over 8

=item Cmd

  Cmd => $command,
  Cmd => [ $command, $arg1, $arg2, ... ],

The command to which to connect.  The passed command may either be a
scalar or an array.

=item Prompt

This specifies one or more prompts to scan for.  For a single prompt,
the value may be a scalar; for more, or for matching of regular
expressions, it should be an array reference.  For example,

  Prompt => 'prompt1> ',
  Prompt => [ 'prompt1> ', 'prompt2> ', -re => 'prompt\d+>\s+' ]

All prompts are taken literally, unless immediately preceded by a C<-re> flag,
in which case they are regular expressions.

=item DisconnectCmd

This is the command to be sent to the target program which will cause
it to exit.

=item RawPty

If set, then underlying B<Expect> object's pty mode is set to raw mode
(see  B<Expect::raw_pty()>).

=item Timeout

The time in seconds to wait until giving up on the target program
responding.  This is used during program startup and when any commands
are sent to the program.  It defaults to 1000 seconds.

=item Debug

The value is passed to B<Expect> via its B<debug> method.

=item Verbose

This results in various messages printed to the STDERR stream.
If greater than 3, it turns on B<Expect>'s logging to STDOUT (via
the B<log_stdout> B<Expect> method.


=back

=item send

   $obj->send( $cmd );
   $obj->send( @cmds );

Send one or more commands to the target.  After each command is sent,
it waits for a prompt from the target.  Only the output resulting from
the last command is available via the B<after>, B<before>, etc. methods.

=item match_idx

This returns a unary based index indicating which prompt (in the list
of prompts specified via the C<Prompt> attribute to the B<new> method)
was received after the last command was sent.  It will be undef if
none was returned.

=item match_str

This returns the prompt which was matched after the last command was sent.

=item before

This returns the string received before the prompt.  If no prompt was seen,
it returns all output accumulated.  This is usually what the caller wants
to parse.  Note that the first line will (usually) be the command that
was sent to the target, because of echoing.  Check this out to be sure!

=item after

This returns the 'after' string.  Please read the B<Expect> docs for more
enlightenment.

=item error

This returns a cleaned up, more humanly readable version of the errors
from B<Expect>.  It'll be undef if there was no error.

=item error_expect

This returns the original B<Expect> error.

=item expect_handle

This returns the B<Expect> object, in case further tweaking is necessary.

=back


=head1 BUGS

If the command to be run does not exist (or not in the current
execution path), it's quite possible that the B<new> method will not
throw an exception.  It's up to the caller to make sure that the command
will run!  There's no known workaround for this.

=head1 LICENSE

This software is released under the GNU General Public License.  You
may find a copy at

   http://www.fsf.org/copyleft/gpl.html

=head1 AUTHOR

Diab Jerius (djerius@cpan.org)

=cut