use strict;
use warnings;
use utf8;
use Test::More;
use Path::Tiny;
use Scope::Guard qw/guard/;

use t::Util;

subtest 'riji setup' => sub {
    my $tmpd = riji_setup;

    for my $file (
        qw(riji.yml cpanfile .gitignore README.md .git/),
        (map { "article/$_" }    qw(archives.md index.md entry/sample.md)),
        (map { "share/tmpl/$_" } qw(base.tx default.tx entry.tx index.tx tag.tx)),
    ) {
        ok -e $file;
    }

    subtest 'riji publish' => sub {
        my $g = guard {
            cmd qw/rm -rf blog/;
        };

        ok ! -d 'blog';
        riji 'publish';
        for my $file (map { "blog/$_" } qw(archives.html index.html entry/sample.html atom.xml) ) {
            ok -e $file;
        }
    };

    subtest 'add new entry' => sub {
        my $new_md = 'article/entry/new.md';
        my $g = guard {
            cmd qw/rm -rf blog/;
        };
        path($new_md)->spew("# new!\n\nnew entry");
        git qw/add/, $new_md;
        git qw/ci -m new!/;
        my ($out, $err, $exit) = riji 'publish';
        for my $file (
            map { "blog/$_" } qw(archives.html index.html entry/sample.html entry/new.html atom.xml)
        ) {
            ok -e $file;
        }
    };

    subtest 'riji publish fails if in dirty entry_dir' => sub {
        my $hoge_md = 'article/entry/hoge.md';
        my $g = guard {
            cmd qw/rm -f/, $hoge_md;
            cmd qw/rm -rf blog/;
        };
        path($hoge_md)->spew('# hoge');
        my ($out, $err, $exit) = riji 'publish';
        cmp_ok $exit, '>', 0;
        like $err, qr/Unknown local files/;
        ok ! -d 'blog';
    };

    subtest 'riji publish success with --force even if in dirty index' => sub {
        my $hoge_md = 'article/entry/hoge.md';
        my $g = guard {
            cmd qw/rm -f/, $hoge_md;
            cmd qw/rm -rf blog/;
        };
        path($hoge_md)->spew('# hoge');
        my ($out, $err, $exit) = riji 'publish --force';
        is $exit, 0;
        ok -e 'blog/entry/hoge.html';
    };
};

done_testing;