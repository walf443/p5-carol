use inc::Module::Install;
use Module::Install::ReadmeFromPod;
use Module::Install::Repository;
name 'Carol';
all_from 'lib/Carol.pm';
readme_from 'lib/Carol.pm';

# requires '';

tests_recursive 't';
author_tests 'xt';

build_requires 'Test::More';
build_requires 'Test::LoadAllModules';
build_requires 'Module::Install::ReadmeFromPod';
use_test_base;
auto_include;
auto_set_repository;
WriteAll;
