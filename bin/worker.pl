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
        my $result = validate($data);
        $agent->post($data->{cb_url}, content_type => 'application/json',
            Content => encode_json($result));
    } catch {
        say "failed: $_";
    };
    $stomp->ack({ frame => $frame });
}
$stomp->disconnect;

# functions -------------------------------------------------------------------

sub validate {
    my ($data) = @_;
    my $problem = $data->{problem};
    my $tmp = File::Temp->new();
    print $tmp $data->{code};
    say "going to run code ...";
    my $input = $problem->{input};
    run [ '/usr/local/bin/perl', "$tmp" ], \$input, \my $out;
    my $status = $out eq $problem->{output} ? 1 : 0;
    my $result = {
        status => $status,
        reason => "I dont know",
        run_id => $data->{run_id},
    };
    dd $result;
    return $result;
}

