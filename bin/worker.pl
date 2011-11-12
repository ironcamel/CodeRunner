#!/usr/bin/env perl
use strict;
use warnings;
use v5.10;
use Data::Dump qw(dd);
use File::Temp;
use FindBin qw($RealBin);
use IPC::Run qw(run timeout);
use JSON qw(decode_json encode_json);
use LWP::UserAgent;
use Net::Stomp;
use Try::Tiny;
use YAML qw(LoadFile);

my $CONFIG = LoadFile("$RealBin/../config.yml");
my $AGENT = LWP::UserAgent->new();

my $stomp = Net::Stomp->new({
    hostname => $CONFIG->{plugins}{Stomp}{default}{hostname},
    port     => $CONFIG->{plugins}{Stomp}{default}{port},
});
$stomp->connect();
$stomp->subscribe({
    destination => $CONFIG->{queue},
    ack         => 'client',
});

while (1) {
    my $frame = $stomp->receive_frame;
    my $msg = $frame->body;
    say "processing...";
    #say "processing $msg";
    try {
        my $data = decode_json($msg);
        validate($data);
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
    my $input = $problem->{input};
    my $reason = "I dont know.";
    say "going to run code ...";
    my $tmp = File::Temp->new();
    print $tmp $data->{code};
    my ($out, $err);
    try {
        run([ '/usr/local/bin/perl', "$tmp" ], \$input, \$out, \$err,
            timeout(3));
    } catch {
        post_result(0, 'Took too long.', $data);
    }
    $out ||= '';
    my $status = $out eq $problem->{output} ? 1 : 0;
    $reason = "Wrong answer." unless $status;
    post_result($status, $reason, $data);
}

sub post_result {
    my ($status, $reason, $data) = @_;
    print "posting result:";
    my $result = {
        status => $status,
        reason => $reason,
        run_id => $data->{run_id},
    };
    dd $result;
    $AGENT->post($data->{cb_url}, content_type => 'application/json',
        Content => encode_json($result));
}
