package CodeRunner;
use v5.10;

use Captcha::reCAPTCHA;
use Dancer ':syntax';
use Dancer::Plugin::Cache::CHI;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Stomp;
use File::Basename qw(fileparse);
use YAML qw(LoadFile DumpFile Bless);

hook before_template_render => sub {
    my $tokens = shift;
    $tokens->{user_id} = session 'user_id';
};

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

post '/login' => sub {
    my $username = param 'username';
    my $password = param 'password';
    my $user = schema->resultset('User')->find($username);
    if ($user and $user->password eq $password) {
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

get '/admin' => sub { template 'admin' };

post '/add_problem' => sub {
    
    if (config->{captcha}{enabled} and
        !check_captcha(param('captcha_challenge'),
                       param('captcha_response'),
                       param('remote_address'))){
        return {captcha_failure => 1}
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
    Bless($problem_data)->keys(['title', 'description',
                                'input_desc', 'output_desc',
                                'sample_input', 'sample_output',
                                'input', 'output']);
    my $filepath = config->{appdir} . "/problems/$prob_name.yml";
    if (-e $filepath){
        return {err_msg => 'A Problem with that title already exists'};
    }
    DumpFile($filepath, $problem_data);

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

post '/ajax/users' => sub {
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
    }
    return 'c++';
}

sub check_captcha {
    my ($challenge, $response, $remote_address) = @_;
    my $c = Captcha::reCAPTCHA->new;

    # Verify submission
    my $result = $c->check_answer(
        config->{captcha}{private_key},
        $remote_address,
        $challenge, $response
    );

    if ( $result->{is_valid} ) {
        return true;
    }
    else {
        # Error
        my $error = $result->{error};
        return false;
    }

}

true;
