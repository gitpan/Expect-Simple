use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'	=> 'Expect::Simple',
    'VERSION_FROM' => 'Simple.pm', # finds $VERSION
    'PREREQ_PM'  => { Expect => 0 }
);
