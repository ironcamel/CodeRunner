package CodeRunner;
use v5.10;

use Dancer ':syntax';
use Dancer::Plugin::Cache::CHI;
use Dancer::Plugin::Stomp;
use File::Basename qw(fileparse);
use YAML qw(LoadFile);

get '/' => sub {
    my @problems;
    for my $path (glob config->{appdir} . '/problems/*.yml') {
        my $problem = LoadFile($path);
        my($name, $dir, $suffix) = fileparse($path, '.yml', '.yaml');
        push @problems,
            { title => $problem->{title}, url => uri_for("/problems/$name") };
    }
    template problems => {
        problems => \@problems,
    };
};

get '/problems/:problem' => sub {
    template problem => {
        problem => get_problem(param 'problem'),
    };
};

post '/problems/:problem' => sub {
    my $problem = get_problem(param 'problem');
    my $file = upload 'code_file';
    my $run_id = session->id;
    cache_set $run_id => to_json({status => -1});
    my $msg = to_json({
        run_id   => $run_id,
        code     => $file->content,
        language => param('language') || guess_lang($file->basename),
        problem  => $problem,
        cb_url   => uri_for('/cb')->as_string,
    }, { utf8 => 1 });
    stomp->send({
        destination => config->{queue},
        body        => $msg,
    });
    template problem => {
        is_running => 1,
        run_id   => $run_id,
        problem  => $problem,
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

sub get_problem {
    my ($prob_name) = @_;
    return LoadFile(config->{appdir} . "/problems/$prob_name.yml");
}

sub guess_lang {
    my ($filename) = @_;
    given ($filename) {
        when (/\.java$/) { return 'java' }
        when (/\.pl$/  ) { return 'perl' }
    }
    return 'c++';
}

true;
