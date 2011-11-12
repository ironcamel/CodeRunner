package CodeRunner;
use v5.10;

use Dancer ':syntax';
use Dancer::Plugin::Cache::CHI;
use Dancer::Plugin::Stomp;
use File::Basename qw(fileparse);
use YAML qw(LoadFile DumpFile Bless);

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

get '/admin' => sub {
    template 'admin';
};

post '/add_problem' => sub {
    my $prob_name = param 'problem_title';
    $prob_name =~ s/\s/-/g;
    my $problem_data = {
        title         => param('problem_title'),
        description   => param('problem_desc'),
        input_desc    => param('problem_input_desc'),
        output_desc   => param('problem_output_desc'),
        sample_input  => param('problem_sample_input'),
        sample_output => param('problem_sample_output'),
        input         => param('problem_input'),
        output        => param('problem_output'),
    };
    local $YAML::UseHeader = 0;
    local $YAML::CompressSeries = 0;
    Bless($problem_data)->keys(['title', 'description',
                                'input_desc', 'output_desc',
                                'sample_input', 'sample_output',
                                'input', 'output']);
    my $filepath = config->{appdir} . "/problems/$prob_name.yml";
    if (-e $filepath){
        return {err_msg => 'A Problem with that title already exists'};
    }
    DumpFile($filepath,
                    $problem_data);

    return {problem_url => uri_for("/problems/$prob_name")->as_string()};

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
        remote   => request->remote_address,
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
        when (/\.py$/  ) { return 'python' }
    }
    return 'c++';
}

true;
