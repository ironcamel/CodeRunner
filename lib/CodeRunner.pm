package CodeRunner;
use v5.10;

use Dancer ':syntax';
use Dancer::Plugin::Cache::CHI;
use Dancer::Plugin::Stomp;
use YAML qw(LoadFile);

get '/' => sub {
    my $problem = LoadFile(config->{appdir} . '/problems/penney.yml');
    template index => {
        problem => $problem,
    };
};

post '/' => sub {
    my $file = upload 'code_file';
    #my $problem = param 'problem';
    my $problem = 'penney';
    my $run_id = session->id;
    cache_set $run_id => to_json({status => -1});
    my $msg = to_json({
        run_id   => $run_id,
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
        run_id => $run_id,
    };
};

get '/status/:run_id' => sub {
    return from_json cache_get param 'run_id';
};

#get '/config' => sub { return to_dumper config };

post '/cb' => sub {
    my $run_id = param 'run_id';
    cache_set $run_id => request->body;
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
