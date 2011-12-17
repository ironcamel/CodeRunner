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
    my $problem = $data->{problem};
    my $out = run_code(
        $lang, $data->{code}, $data->{file_name}, $problem->{input});
    my $status = $out eq $problem->{output} ? 1 : 0;
    my $reason = $status == 1 ? 'Success' : 'Wrong answer';
    post_result($status, $reason, $data);
}

sub run_code {
    my ($lang, $code, $file_name, $input) = @_;
    say "going to run code ...";
    my ($out, $err) = ('', '');
    my @cmd;
    
    my $tmpdir = File::Temp->newdir();
    my $tmpfile = File::Temp->new();
    given ($lang) {
        when ('java') {
            my $class_name = (split /\./, $file_name)[0];
            my $path = "$tmpdir/$file_name";
            open my $java_file, '>', $path;
            print $java_file $code;
            run([ 'javac', "$path" ]) or die "Failed to compile java code";
            @cmd = ($lang, -classpath => "$tmpdir", $class_name);
        }
        when ('c++') {
            my $path = "$tmpdir/foo.cpp";
            open my $c_file, '>', $path;
            print $c_file $code;
            run([ 'g++', '-o' => "$tmpdir/foo", "$path" ])
                or die "Failed to compile c/c++ code";
            @cmd = ("$tmpdir/foo");
        }
        when ([qw(perl python java)]) {
            print $tmpfile $code;
            @cmd =($lang, "$tmpfile");
        }
        default {
            die "Language [$lang] is not supported yet\n";
        }
    }
    try {
        debug("going to run code: @cmd");
        run(\@cmd, \$input, \$out, \$err, timeout(3));
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
