#!/usr/bin/env perl
use strict;
use warnings;
use v5.10;
use JSON qw(from_json to_json);
use File::Temp;
use FindBin qw($RealBin);
use IPC::Run qw(run);
use LWP::UserAgent;
use Net::Stomp;
use Try::Tiny;
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
    sleep 1; # need time for websocket to connect
    my $msg = $frame->body;
    print "processing $msg\n";
    try {
        my $data = from_json($msg);
        my $problem = $data->{problem};
        my $tmp = File::Temp->new();
        print $tmp $data->{code};
        say "going to run code ...";
        my $input = $problem->{input};
        run [ '/usr/local/bin/perl', "$tmp" ], \$input, \my $out;
        my $status = $out eq $problem->{output} ? 1 : 0;
        my $body = to_json({
            status => $status,
            reason => "I dont know",
            run_id => $data->{run_id},
        });
        say "result: $body";
        $agent->post($data->{cb_url}, content_type => 'application/json',
            Content => $body);
    } catch {
        say "failed: $_";
    };
    $stomp->ack({ frame => $frame });
}
$stomp->disconnect;
