#!/usr/bin/env perl
use strict;
use warnings;
use v5.10;
use Data::Dump qw(dd dump);
use File::Temp;
use FindBin qw($RealBin);
use IO::File;
use IPC::Run qw(run timeout);
use JSON qw(decode_json encode_json);
use LWP::UserAgent;
use Net::Stomp;
use Try::Tiny;
use YAML qw(LoadFile);

my $CONFIG = LoadFile("$RealBin/../config.yml");
my $AGENT = LWP::UserAgent->new();
my $log_path = "coderunner-worker.log";
my $LOG = IO::File->new($log_path, 'a')
    or die "Could not open $log_path : $!\n";

my $stomp = Net::Stomp->new({
    hostname => $CONFIG->{plugins}{Stomp}{default}{hostname},
    port     => $CONFIG->{plugins}{Stomp}{default}{port},
});
$stomp->connect();
$stomp->subscribe({
    destination => $CONFIG->{queue},
    ack         => 'client',
});

$SIG{INT} = sub {
    $stomp->disconnect;
    say 'goodbye';
    exit;
};

while (1) {
    my $frame = $stomp->receive_frame;
    my $msg = $frame->body;
    my $data;
    say "processing msg ...";
    try {
        $data = decode_json($msg);
        validate($data);
    } catch {
        chomp;
        say "failed: $_";
        post_result(0, $_, $data);
    };
    $stomp->ack({ frame => $frame });
}
$stomp->disconnect;

# functions -------------------------------------------------------------------

sub validate {
    my ($data) = @_;
    log_msg($data);
    my $lang = $data->{language};
    die "Language not supported yet.\n"
        unless $lang ~~ [qw(perl python ruby java)];
    my $problem = $data->{problem};
    my $out = run_code($lang, $data->{code}, $problem->{input});
    my $status = $out eq $problem->{output} ? 1 : 0;
    my $reason = $status == 1 ? '' : 'Wrong answer.';
    post_result($status, $reason, $data);
}

sub run_code {
    my ($lang, $code, $input) = @_;
    say "going to run code ...";
    my ($out, $err) = ('', '');
    my $tmp = File::Temp->new();
    print $tmp $code;
    try {
        run([ $lang, "$tmp" ], \$input, \$out, \$err, timeout(3));
    } catch {
        die "Took too long\n";
    };
    return $out;
}

sub post_result {
    my ($status, $reason, $data) = @_;
    print "posting result:";
    my $result = {
        status  => $status,
        reason  => $reason,
        run_id  => $data->{run_id},
        user_id => $data->{user_id},
        problem => $data->{problem}{title},
    };
    dd $result;
    debug($result);
    $AGENT->post($data->{cb_url}, content_type => 'application/json',
        Content => encode_json($result));
}

sub debug {
    print $LOG '[' . localtime . '] (DEBUG) ';
    say $LOG dump(@_);
    $LOG->flush;
}

sub log_msg {
    my $data = shift;
    my %copy = %$data;
    $copy{problem} = $copy{problem}{title};
    debug(\%copy)
}
