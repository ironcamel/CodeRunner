package CodeRunner;
use v5.10;

use Dancer ':syntax';
#use Dancer::Plugin::Ajax;
use Dancer::Plugin::Stomp;
use Dancer::Plugin::WebSocket;

get '/' => sub {
    template 'index';
};

post '/' => sub {
    my $file = upload 'code_file';
    #my $problem = param 'problem';
    my $problem = 'penney';
    my $msg = to_json({
        id       => session->id,
        code     => $file->content,
        filename => $file->basename,
        language => param('language') || guess_lang($file->basename),
        problem  => config->{problems}{$problem},
        cb_url   => uri_for('/cb')->as_string,
    }, { pretty => 1 });
    stomp->send({
        destination => config->{queue},
        body        => $msg,
    });
    template index => {
        is_running => 1,
        session_id => session->id,
    };
};

post '/cb' => sub {
    my $status = param 'status';
    my $reason = param 'reason';
    ws_send to_json({
        status => $status,
        reason => $reason,
    });
    return '';
};

sub guess_lang {
    my ($filename) = @_;
    given ($filename) {
        when (/\.java$/) { return 'java' }
        when (/\.pl$/  ) { return 'perl' }
    }
    return 'c++';
}

true;
