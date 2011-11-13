package CodeRunner;
use v5.10;

use Captcha::reCAPTCHA;
use Dancer ':syntax';
use Dancer::Plugin::Cache::CHI;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Stomp;
use DateTime;
use File::Basename qw(fileparse);
use YAML qw(LoadFile DumpFile Bless);

# Automagically create db tables the first time this app is run
eval { schema->resultset('User')->count };
schema->deploy if $@;

hook before_template_render => sub {
    my $tokens = shift;
    $tokens->{user_id} = session 'user_id';
};

get '/' => sub {
    my @problems;
    for my $path (glob config->{appdir} . '/problems/*.yml') {
        my $problem = LoadFile($path);
        my($name, $dir, $suffix) = fileparse($path, '.yml', '.yaml');
        my $attempts = schema->resultset('Attempt')->search({
            problem => $problem->{title},
        })->count;
        my $solved = schema->resultset('Attempt')->search({
            problem    => $problem->{title},
            is_success => 1,
        })->count;
        push @problems, {
            title    => $problem->{title},
            attempts => $attempts,
            solved => $solved,
            url      => uri_for("/problems/$name")
        };
    }

    template problems => {
        problems => \@problems,
    };
};

get '/leaderboard' => sub {
    #select user_id, count(distinct problem) from attempt where is_success=1 group by user_id;
    my @attempts = schema->resultset('Attempt')->search(
        { is_success => 1 },
        {
            select    => [ 'user_id', { count => {distinct => 'problem'},
                                        -as => 'num_solved'}
                         ],
            as        => [ 'user_id', 'num_solved' ],
            group_by  => 'user_id',
            order_by  => { -desc => 'num_solved' },
        }
    );
    template leaderboard => {
        active_nav => 'rankings',
        leaders    => [ map +{ $_->get_columns }, @attempts ],
    };
};

get '/login' => sub {
    if (param 'failed') {
        template 'bad_login';
    }
    else {
        redirect uri_for '/';
    }
};

post '/login' => sub {
    my $username = param 'username';
    my $password = param 'password';

    # admin special case
    my $is_admin = (($username eq 'admin') and ($password eq config->{admin_pass}));

    my $user = schema->resultset('User')->find($username);
    if ($is_admin or ($user and $user->password eq $password)) {
        session user_id => $username;
        redirect uri_for '/';
    } else {
        session user_id => undef;
        redirect uri_for('/login', { failed => 1 });
    }
};

get '/logout' => sub {
    session->destroy;
    redirect uri_for '/';
};

get '/admin' => sub { 
    my $user_id = session 'user_id';
    if(not $user_id eq 'admin'){
        redirect uri_for '/';
    }
    template 'admin' => {active_nav => 'admin'}
};


post '/add_problem' => sub {
    
    if (config->{captcha}{enabled}) {
        return { captcha_failure => 1 }
            unless check_captcha(
                param('captcha_challenge'),
                param('captcha_response'),
                param('remote_address'));
    }

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
    Bless($problem_data)->keys([qw(title description input_desc output_desc
        sample_input sample_output input output)]);
    my $filepath = config->{appdir} . "/problems/$prob_name.yml";
    if (-e $filepath){
        return {err_msg => 'A Problem with that title already exists'};
    }
    DumpFile($filepath, $problem_data);

    my $problem = { name => $problem_data->{title} };
    debug "Creating new problem: ", $problem;
    eval { schema->resultset('Problem')->create($problem) };
    if ($@) {
        error $@;
        return { err_msg =>  "The problem '$problem' is already taken." }
            if $@ =~ /column id is not unique/;
        return { err_msg => "Could not create problem '$problem': $@." };
    }

    return { problem_url => uri_for("/problems/$prob_name")->as_string() };

};

get '/problems/:problem' => sub {
    template problem => {
        problem => get_problem(param 'problem'),
    };
};

del '/problems/:problem' => sub {
    my $prob_name = param 'problem';
    my $problem = get_problem($prob_name); 
    my $filepath = config->{appdir} . "/problems/$prob_name.yml";
    if (-e $filepath) {
        return { err_msg => "yml file for $prob_name could not be deleted" }
            unless unlink $filepath;
    }
    schema->resultset('Problem')->search({ name => $problem->{title} })
          ->delete_all();
    return {};
};

get '/problems/:problem/print-friendly' => sub {
    set layout => 'print_friendly';
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
        user_id  => session('user_id'),
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

post '/cb' => sub {
    my $run_id = param 'run_id';
    my $json = request->body;
    cache_set $run_id => $json;

    my $data = from_json $json;
    debug $data;
    my $user_id = $data->{user_id};
    return unless $user_id;
    my $user = schema->resultset('User')->find($user_id);
    return unless $user_id;

    $user->add_to_attempts({
        problem    => $data->{problem},
        reason     => $data->{reason},
        time_of    => DateTime->now,
        is_success => $data->{status},
    });
};

post '/ajax/users' => sub {

    if (config->{captcha}{enabled}) {
        return { err_msg => 'The CAPTCHA is incorrect.', captcha_failure => 1 }
            unless check_captcha(
                param('captcha_challenge'),
                param('captcha_response'),
                param('remote_address'));
    }

    my $username = param 'username'
        or return { err_msg => 'The username is missing.' };
    my $password = param 'password'
        or return { err_msg => 'The password is missing.' };
    my $email = param 'email';
    if ($email and $email !~ /.+@..+\...+/) {
        return { err_msg => "The email [$email] is invalid." }
    }
    my $user = {
        id       => $username,
        password => $password,
        $email ? (email => $email) : (),
    };
    debug "Creating new user: ", $user;
    eval { schema->resultset('User')->create($user) };
    if ($@) {
        error $@;
        return { err_msg =>  "The username '$username' is already taken." }
            if $@ =~ /column id is not unique/;
        return { err_msg => "Could not create user '$username': $@." };
    }
    return { is_success => 1 };
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
        when (/\.rb$/  ) { return 'ruby' }
    }
    return 'c++';
}

sub check_captcha {
    my ($challenge, $response, $remote_address) = @_;
    my $c = Captcha::reCAPTCHA->new;
    my $result = $c->check_answer(config->{captcha}{private_key},
        $remote_address, $challenge, $response);
    #my $error = $result->{error};
    return $result->{is_valid};
}

true;
