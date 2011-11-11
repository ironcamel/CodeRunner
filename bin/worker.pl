#!/usr/bin/env perl
use strict;
use warnings;
use v5.10;
use Data::Dump qw(dd dump);
use File::Temp;
use FindBin qw($RealBin);
use IPC::Run qw(run);
use JSON qw(decode_json encode_json);
use LWP::UserAgent;
use Net::Stomp;
use Try::Tiny;
use Unix::PID::Tiny;
use YAML qw(LoadFile);

my $config = LoadFile("$RealBin/../config.yml");
my $agent = LWP::UserAgent->new();

my $stomp = Net::Stomp->new({
    hostname => $config->{plugins}{Stomp}{default}{hostname},
    port     => $config->{plugins}{Stomp}{default}{port},
});
$stomp->connect();
$stomp->subscribe({
    destination => $config->{queue},
    ack         => 'client',
});

while (1) {
    my $frame = $stomp->receive_frame;
    my $msg = $frame->body;
    print "processing $msg\n";
    try {
        my $data = decode_json($msg);
        my $result = validate($data, $agent);
        #$agent->post($data->{cb_url}, content_type => 'application/json',
            #Content => encode_json($result));
    } catch {
        say "failed: $_";
    };
    $stomp->ack({ frame => $frame });
}
$stomp->disconnect;

# functions -------------------------------------------------------------------

sub validate {
    my ($data, $agent) = @_;
    my $problem = $data->{problem};
    my $input = $problem->{input};
    say "going to run code ...";
    my $pid = fork;
    if ($pid == 0) { # this is the child process
        my $tmp = File::Temp->new();
        #print $tmp $data->{code};
        run [ '/usr/local/bin/perl', "$tmp" ], \$input, \my $out;
        $out ||= '';
        my $status = $out eq $problem->{output} ? 1 : 0;
        my $result = {
            status => $status,
            reason => "I dont know",
            run_id => $data->{run_id},
        };
        $agent->post($data->{cb_url}, content_type => 'application/json',
            Content => encode_json($result));
        exit;
    }
    #sleep 6;
    #dd $result;
    #return $result;
}

