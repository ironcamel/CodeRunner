use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'CodeRunner',
    AUTHOR       => 'Naveed Massjouni <naveedm9@gmail.com>',
    VERSION_FROM => 'lib/CodeRunner.pm',
    ABSTRACT     => 'A webapp for programming puzzles and contests',
    LICENSE      => 'perl',
    PL_FILES     => {},
    PREREQ_PM => {
        'Dancer'                    => 1.3072,
        'Dancer::Plugin::Stomp'     => 0,
        'Dancer::Plugin::WebSocket' => 0,
        'YAML'                      => 0,
        'JSON'                      => 0,
        'Template'                  => 0,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
    clean => { FILES => 'CodeRunner-*' },
);
