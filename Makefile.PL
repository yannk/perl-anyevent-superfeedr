use inc::Module::Install;
name 'AnyEvent-Superfeedr';
all_from 'lib/AnyEvent/Superfeedr.pm';

build_requires 'Test::More';
use_test_base;
auto_include_deps;
author_tests('xt');
auto_set_repository;
githubmeta;
WriteAll;
