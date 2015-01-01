package Riji::CLI::Publish;
use feature ':5.10';
use strict;
use warnings;

use Errno qw(:POSIX);
use Path::Tiny qw/path tempdir/;
use File::Copy::Recursive qw/dircopy/;

use Riji::CLI::Publish::Scanner;
use Wallflower::Util qw/links_from/;
use URI;

use Riji;

sub run {
    my ($class, @argv) = @_;

    my $app = Riji->new;
    my $conf = $app->config;
    my $repo = $app->model('Blog')->repo;
    my $force = grep {$_ eq '--force'} @argv;

    # `git symbolic-ref --short` is available after git 1.7.10, so care older version.
    my $current_branch = $repo->run(qw/symbolic-ref HEAD/);
       $current_branch =~ s!refs/heads/!!;
    my $publish_branch = $app->model('Blog')->branch;
    unless($force){
        if ($publish_branch ne $current_branch) {
            die "You need at publish branch [$publish_branch], so `git checkout $publish_branch` beforehand\n";
        }

        if ( my $untracked = $repo->run(qw/ls-files --others --exclude-standard/) ) {
            die "Unknown local files:\n$untracked\n\nUpdate .gitignore, or git add them\n";
        }

        if (my $uncommited = $repo->run(qw/diff HEAD --name-only/) ) {
            die "Found uncommited changes:\n$uncommited\n\ncommit them beforehand\n";
        }
    }

    say "start scanning";
    my $replace_from = quotemeta "http://localhost";
    my $replace_to   = $conf->{site_url};
       $replace_to =~ s!/+$!!;

    my $site_url = URI->new($conf->{site_url});

    my $dir = $conf->{publish_dir} // 'blog';
    unless (mkdir $dir or $! == EEXIST ){
        printf "can't create $dir: $!\n";
    }

    my $work_dir = tempdir(CLEANUP => 1);

    my $mount_path = $site_url->path;
       $mount_path = '' if $mount_path eq '/';

    my $wallflower = Riji::CLI::Publish::Scanner->new(
        application => $app->to_psgi,
        destination => $work_dir . '',
        $mount_path ? (mount => $mount_path) : (),
        server_name => $site_url->host,
        $site_url->scheme ne 'http' ? (scheme => $site_url->scheme) : (),
    );
    my $host_reg = quotemeta $site_url->host;

    my %seen;
    my @queue = ($site_url->path || '/');
    while (@queue) {
        my $url = URI->new( shift @queue );
        next if $seen{ $url->path }++;
        next if $url->scheme && ! eval { $url->host =~ /(?:localhost|$host_reg)/ };

        # get the response
        my $response = $wallflower->get($url);
        my ( $status, $headers, $file ) = @$response;

        # tell the world
        printf "$status %s %s\n", $url->path, $file && "[${\-s $file}]";

        # obtain links to resources
        if ( $status eq '200' ) {
            push @queue, links_from( $response => $url );
        }

        if ($file && $file =~ /\.(?:js|css|html|xml)$/) {
            $file = path($file);
            my $content = $file->slurp_utf8;
            $content =~ s/$replace_from/$replace_to/msg;
            $file->spew_utf8($content);
        }
    }

    my $copy_from = $work_dir;
    if ($site_url->path !~ m!^/?$!) {
        my $mount = $site_url->path;
        $mount =~ s!^/+!!;
        $copy_from = path($work_dir, $mount);
    }
    dircopy($copy_from.'', $dir);

    say "done.";
}

1;
