use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'CodeRunner',
    AUTHOR       => 'Naveed Massjouni <naveedm9@gmail.com>',
    VERSION_FROM => 'lib/CodeRunner.pm',
    ABSTRACT     => 'A webapp for ACM style programming puzzles and contests',
    LICENSE      => 'perl',
    PL_FILES     => {},
    PREREQ_PM => {
        'Cache::FastMmap'            => '0',
        'Captcha::reCAPTCHA'         => '0',
        'Dancer'                     => '1.3080',
        'Dancer::Plugin::Cache::CHI' => '0',
        'Dancer::Plugin::DBIC'       => '0',
        'Dancer::Plugin::Stomp'      => '1.0100',
        'Dancer::Plugin::Passphrase' => '0',
        'Data::Dump'                 => '0',
        'DateTime'                   => '0',
        'IPC::Run'                   => '0',
        'JSON'                       => '0',
        # Need this and libssl-dev for https support
        #'LWP::Protocol::https'       => '0',
        'LWP::UserAgent'             => '0',
        'Math::Random::Secure'       => '0',
        'Net::STOMP::Client'         => '0',
        'SQL::Translator'            => '0.11006',
        'Template'                   => '0',
        'Try::Tiny'                  => '0',
        'YAML'                       => '0',
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
    clean => { FILES => 'CodeRunner-*' },
);
