package CodeRunner;
use v5.10;

use Captcha::reCAPTCHA;
use Dancer ':syntax';
use Dancer::Plugin::Cache::CHI;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Passphrase;
use Dancer::Plugin::Stomp;
use DateTime;
use Math::Random::Secure qw(irand);

# Automagically create db tables the first time this app is run
eval { schema->resultset('User')->count };
schema->deploy if $@;

hook before_template_render => sub {
    my $tokens = shift;
    $tokens->{user_id} = session 'user_id';
};

get '/' => sub {
    my @problems;
    for my $problem (schema->resultset('Problem')->all) {
        my $attempts = $problem->attempts->count;
        my $solved = $problem->attempts->search({ is_success => 1 })->count;
        push @problems, {
            title    => $problem->title,
            attempts => $attempts,
            solved   => $solved,
            url      => uri_for("/problems/" . $problem->id)
        };
    }

    template problems => {
        active_nav => 'home',
        problems   => \@problems,
    };
};

get '/leaderboard' => sub {
    #select user_id, count(distinct problem) from attempt
    #    where is_success=1 group by user_id;
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
    param('failed') ? template('bad_login') : redirect uri_for '/';
};

post '/login' => sub {
    my $username = param 'username';
    my $password = param 'password';
    my $passphrase = passphrase($password);

    my $is_admin;
    if (config->{admin_pass}) {
        $is_admin = $username eq 'admin' && $password eq config->{admin_pass};
    }

    my $user = schema->resultset('User')->find($username);
    if ($is_admin or ($user and $passphrase->matches($user->password))) {
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
    return redirect uri_for '/' unless 'admin' eq session 'user_id';
    template admin => { active_nav => 'admin' };
};

post '/add_problem' => sub {
    
    if (config->{captcha}{enabled}) {
        return { captcha_failure => 1 } unless check_captcha(
            param('captcha_challenge'),
            param('captcha_response'),
            param('remote_address'));
    }

    my $prob_name = param 'problem_title';
    $prob_name =~ s/\s/-/g;
    my %problem_data = (
        title         => param('problem_title'),
        description   => param('problem_desc'),
        input_desc    => param('problem_input_desc'),
        output_desc   => param('problem_output_desc'),
        sample_input  => param('problem_sample_input'),
        sample_output => param('problem_sample_output'),
        input         => param('problem_input'),
        output        => param('problem_output'),
    );

    # Make sure input and output fields end with a newline
    foreach (@problem_data{qw(input output)}) { chomp; $_ .= "\n" };

    my $title = $problem_data{title};
    debug "Creating new problem: $title";
    my $prob_row = eval {schema->resultset('Problem')->create(\%problem_data)};
    if ($@) {
        error "Failed to create new problem: $@";
        return { err_msg =>  "The problem '$title' is already taken." }
            if $@ =~ /column .* is not unique/;
        return { err_msg => "Could not create problem '$title': $@." };
    }

    return { problem_url => uri_for("/problems/") . $prob_row->id };
};

get '/problems/:problem_id' => sub {
    template problem => {
        problem => get_problem(),
    };
};

del '/problems/:problem_id' => sub {
    my $id = param 'problem_id';
    schema->resultset('Problem')->find($id)->delete();
    return {};
};

get '/problems/:problem_id/print-friendly' => sub {
    template problem => {
        problem => get_problem(),
    }, { layout => 'print_friendly' };
};

post '/problems/:problem_id' => sub {
    debug "handling post => ", request->path;
    my $problem = get_problem();
    my $file = upload 'code_file';
    my $run_id = irand(1_000_000_000);
    cache_set $run_id => to_json({status => -1});
    my $msg = to_json({
        run_id   => $run_id,
        user_id  => session('user_id'),
        code     => $file->content,
        language => guess_lang($file->basename),
        problem  => { $problem->get_columns },
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

get '/help' => sub { template help => { active_nav => 'help' } };

get '/status/:run_id' => sub { from_json cache_get param 'run_id' };

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
        password => passphrase($password)->generate_hash,
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

sub get_problem { schema->resultset('Problem')->find(param 'problem_title') }

sub guess_lang {
    my ($filename) = @_;
    given ($filename) {
        when (/\.cpp$/ ) { return 'c++'    }
        when (/\.java$/) { return 'java'   }
        when (/\.pl$/  ) { return 'perl'   }
        when (/\.py$/  ) { return 'python' }
        when (/\.rb$/  ) { return 'ruby'   }
    }
    return '';
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
