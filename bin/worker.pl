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
use Net::STOMP::Client;
use POSIX qw(setgid);
use Try::Tiny;
use YAML qw(LoadFile);

my $CONFIG = LoadFile("$RealBin/../config.yml");
my $AGENT = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
my $log_path = "/tmp/coderunner-worker.log";
my $LOG = IO::File->new($log_path, 'a')
    or die "Could not open $log_path : $!\n";

my $stomp = Net::STOMP::Client->new(
    host => $CONFIG->{plugins}{Stomp}{default}{hostname},
    port => $CONFIG->{plugins}{Stomp}{default}{port},
);
$stomp->message_callback(sub { return 1 });
$stomp->connect();
$stomp->subscribe(destination => $CONFIG->{queue}, ack => 'client');

$SIG{INT} = sub {
    $stomp->disconnect;
    say 'goodbye';
    exit;
};
$SIG{PIPE} = 'IGNORE';

while (1) {
    my $frame = $stomp->wait_for_frames();
    my $msg = $frame->body;
    my $data;
    say "processing msg ...";
    try {
        $data = decode_json($msg);
        validate($data);
    } catch {
        debug("failed to process msg: $_");
        post_result(0, $_, $data);
    };
    $stomp->ack(frame => $frame);
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
    debug("going to run code ...");

    my $jail = '/var/chroot1';
    my $cmd = "rm -rf $jail";
    debug($cmd);
    system $cmd;

    $cmd = "tar -xf $jail.tar -C /var";
    debug($cmd);
    die "Could not build chroot jail: $!" unless system($cmd) == 0;

    chdir $jail or die "Failed to chdir into $jail: $!";

    my $pid = open my $child_process, '-|';
    if (!$pid) { # child process starts here

        debug("chroot $jail");
        chroot $jail or die "could not chroot: $!";

        # drop root privileges
        my $new_uid = getpwnam('coderunner');
        unless (defined $new_uid) {
            say "Can't find uid for 'coderunner'";
            exit 1;
        }
        $< = $> = $new_uid;
        setgid($new_uid);

        my ($out, $err, @cmd) = ('', '');
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

        debug("going to run: @cmd");
        try {
            run(\@cmd, \$input, \$out, \$err, timeout(3));
        } catch {
            print "Took too long\n";
        };
        print $out;
        exit;
    } # end of child process

    # Read output from the child process
    my @out = <$child_process>;
    close $child_process;
    my $result = join '', @out;
    debug('output: ' . substr $result, 0, 100);

    # Lets clean up after ourselves.
    $cmd = "rm -rf $jail";
    debug($cmd);
    system $cmd;

    return $result;
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
    debug("going to post result to callback url: $data->{cb_url}");
    my $res = $AGENT->post($data->{cb_url}, content_type => 'application/json',
        content => encode_json($result));
    debug($res->status_line);
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
