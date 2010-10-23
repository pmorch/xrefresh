#!/usr/bin/perl -w
use strict;
use Socket;
use JSON::XS;
use Data::Dumper;
use IO::Select;
use IO::Socket::INET;
use IO::File;

=head1 Cross Platform Xrefresh server

This is supported on all platforms where perl is supported.

This server listens for incoming TCP connections on TCP port 4444. When it
recieves such a connection, it sends a message to the xrefresh plugin (that has
established a connection with this server beforehand) so browser pages can be
refreshed. It also expects to get a single line and prints it out.

It works differently than the other existing monitors for Xrefresh. They
monitor a directory of files and notify the browser if any of them have
changed. True to *NIX tradition, I decided that another tool could do that. I
just wanted a simple way to tell the browser to refresh. And so here it is:

    echo "Project changed" | nc localhost 4444

Now your browser will refresh (nc is king!)

=cut

my $xrefreshPort  = 41258;
my $controlPort = 4444;
my $messageSeparator = "---XREFRESH-MESSAGE---";

sub logMsg {
    my ($msg) = @_;
    print $msg, "\n";
}

sub readMsg {
    my ($client) = @_;
    my $msg = '';
    while ($msg !~ /$messageSeparator$/) {
        my $char;
        my $nrRead = read $client, $char, 1;
        if (! $nrRead) {
            if ($client->eof) {
                return undef;
            } else {
                die "Couldn't read from client";
            }
        }
        $msg .= $char;
    }
    $msg =~ s/$messageSeparator$//;
    return decode_json($msg);
}

sub handleMsg {
    my ($client, $msg) = @_;
    print "Handling command: $msg->{command}\n";
    # print Dumper($msg);
    if ($msg->{command} eq 'Hello') {
        my $response = {
            command => 'AboutMe',
            agent => 'XRefresh',
            version => '1.1',
        };
        writeMsg($client, $response);
    } elsif ($msg->{command} eq 'SetPage') {
        # Don't do anything about this one
    } else {
        warn "Dunno about $msg->{command}";
    }
}


sub writeMsg {
    my ($client, $msg) = @_;
    print $client encode_json($msg), $messageSeparator;
}

my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
$year+=1900;
$mon+=1;

# We have this hard-coded change for now
my $change = {
    "date"=>sprintf("%02d-%02d-%04d", $mday, $mon, $year),
    "time"=>sprintf("%02d:%02d:%02d", $hour, $min, $sec),
    "root"=>"/bogus",
    "name"=>"Bogus",
    "type"=>undef,
    "files"=>[
        # I guess we could set up this later. I haven't needed it yet
        # {
        #     "action"=>"changed",
        #     "path1"=>"somefile.ext",
        #     "path2"=>undef,
        # }
    ],
    "contents"=>{},
    "command"=>"DoRefresh",
};

my $sel = new IO::Select();

my $lsn = new IO::Socket::INET( 
    Listen => 1, LocalPort => $xrefreshPort, Reuse => 1
);
$sel->add($lsn);

my $control = new IO::Socket::INET(
    Listen => 5, Proto => 'tcp', LocalPort => $controlPort, Reuse => 1
);
$sel->add($control);

my $lastClient;
do {
    # print "Loop\n";

    # Ok so we really don't need the timeout value here, but if the print above
    # is uncommented it allows us to see that we're not hanging somewhere.
    my @ready = $sel->can_read(2);

    foreach my $fh (@ready) {
        if ( $fh == $lsn ) {
            # Create a new socket
            print "New connection\n";
            my $new = $lsn->accept;
            $sel->add($new);
            $lastClient = $new;
        } elsif ( $fh == $control ) {
            my $new = $control->accept;
            my $line = <$new>;
            if ($line) {
                chomp $line;
                print "Control message recieved: $line\n";
                if ($lastClient) {
                    writeMsg($lastClient, $change);
                }
            }
            $new->close();
        } else {
            my $msg = readMsg($fh);
            if (! $msg && $fh->eof()) {
                print "Connection closed\n";
                # Maybe we have finished with the socket
                $sel->remove($fh);
                $fh->close;
                $lastClient = undef;
                next;
            }
            handleMsg($fh, $msg);
        }
    }

    # sleep 1;
} while (1);
