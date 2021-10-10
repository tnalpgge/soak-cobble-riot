#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use File::Basename;
use File::Find ();
use File::Glob qw(:bsd_glob);
use File::Spec;
use IO::Pipe;
use JSON;
use Log::Log4perl;
use LWP::UserAgent;
use Mac::PropertyList::SAX;
use String::ShellQuote;
use URI;
use URI::Escape;
#use YAML;

my $l4p = q(
log4perl.rootLogger = INFO, SCREEN
log4perl.appender.SCREEN = Log::Log4perl::Appender::ScreenColoredLevels
log4perl.appender.SCREEN.layout = Log::Log4perl::Layout::SimpleLayout
);
Log::Log4perl->init(\$l4p);
my $logger = Log::Log4perl->get_logger();

my $ua = LWP::UserAgent->new(timeout => 5);

# Set the variable $File::Find::dont_use_nlink if you're using AFS,
# since AFS cheats.

# for the convenience of &wanted calls, including -eval statements:
use vars qw/*name *dir *prune/;
*name   = *File::Find::name;
*dir    = *File::Find::dir;
*prune  = *File::Find::prune;

sub wanted;

# Traverse desired filesystems
File::Find::find({wanted => \&wanted}, bsd_glob("~/Downloads", GLOB_TILDE));

my %candidates;
sub wanted {
    my ($dev,$ino,$mode,$nlink,$uid,$gid) = lstat($_);
    if ((-f _) && (-r _) && ((/^.*\.epub\z/s) || (/^.*\.pdf\z/s)))
    {
	my $b = basename($name);
	$candidates{basename($name)} = $name;
	#$logger->debug("$b => $name");
    }
}

sub file_or_candidate
{
    my $value = shift;
    if ((-f $value) && (-r $value))
    {
	$logger->debug("$value exists and is readable");
	return $value;
    }
    $logger->debug("Looking for replacement for $value");
    my $candidate = $candidates{basename($value)};
    if ($candidate && (-f $candidate) && (-r $candidate))
    {
	$logger->debug("Found plausible replacement candidate $candidate");
	return $candidate;
    }
    $logger->debug("No plausible replacement found for $value");
    return undef;
}

sub trim
{
    my $x = shift;
    $x =~ s/^\s*//;
    $x =~ s/\s$//;
    $x =~ s/\s+/ /g;
    return $x;
}

sub plash
{
    my %entry = @_;
    my %plash;
    $logger->debug("Extracting information from plist entry");
    $logger->debug(%entry);
    for my $i (qw(itemName BKDisplayName))
    {
	if ((exists $entry{$i}) && $entry{$i})
	{
	    $plash{'--title'} ||= trim($entry{$i}->value);
	}
    }
    if ((exists $entry{'artistName'}) && $entry{'artistName'})
    {
	$plash{'--authors'} = trim($entry{'artistName'}->value);	
    }
    else
    {
	$plash{'--authors'} = "Unknown Author";
    }
    for my $i (qw(sourcePath path))
    {
	next unless ((exists $entry{$i}) && $entry{$i});
	my $candidate = file_or_candidate($entry{$i}->value);
	if ($candidate)
	{
	    $logger->debug($candidate);
	    $plash{'file'} ||= $candidate;
	}
    }
    $logger->debug("Most plausible file ", $plash{'file'});
    if (exists $plash{'--authors'})
    {
	$logger->debug("Authors: ", $plash{'--authors'});
    }
    if (exists $plash{'--title'})
    {
	$logger->debug("Title: ", $plash{'--title'});
    }    
    return %plash;
}

sub isdup
{
    my %plash = @_;
    my $uri = URI->new();
    $uri->scheme("http");
    $uri->host("localhost");
    $uri->port(8081);
    $uri->path("interface-data/books-init");
    my %search;
    while (my ($k, $v) = each %plash)
    {
	if ($k eq '--authors')
	{
	    $search{'author'} = $v;
	}
	if ($k eq '--title')
	{
	    $search{'title'} = $v;
	}
    }
    my @search;
    while (my ($k, $v) = each %search)
    {
	push @search, sprintf(qq(%s:"%s"), $k, $v);
    }
    my $search = join(" ", @search);
    $uri->query_form(
	library_id => "Calibre_Library",
	search => $search,
	);
    $logger->debug($uri);
    my $response = $ua->get($uri);
    $logger->debug($response->status_line());
    unless ($response->is_success())
    {
	$logger->warn("Failed or missing response from Calibre content server?!");
	return 1;
    }
    my $content;
    eval {
	$content = decode_json($response->decoded_content());
    };
    if ($@)
    {
	$logger->warn("Response from Calibre not valid JSON?!");
	return 1;
    }
    if ($content->{'search_result'}->{'total_num'} < 1)
    {
	$logger->debug("Search yielded no results, therefore not a duplicate");
	return 0;
    }
    my $matched_author = 0;
    my $matched_title = 0;
    for my $result (@{$content->{'search_result'}->{'book_ids'}})
    {
	my $book = $content->{'metadata'}->{$result};
	if (exists $plash{'--authors'})
	{
	    $logger->debug("Searching for author: ", $plash{'--authors'});
	    for my $author (@{$book->{'authors'}})
	    {
		$logger->debug("Testing author: ", $author);
		if ($plash{'--authors'} eq $author)
		{
		    $logger->debug("Search found a book with this author");
		    $matched_author = 1;
		    last;
		}
	    }
	    unless ($matched_author)
	    {
		$logger->debug("Search did not find a book with this author");
	    }
	}
	if (exists $plash{'--title'})
	{
	    if ($plash{'--title'} eq $book->{'title'})
	    {
		$logger->debug("Search found a book with this title");
		$matched_title = 1;
	    }
	}
    }
    if ($matched_author && $matched_title)
    {
	$logger->debug("Calibre already knows of a book with this author and title");
	return 1;
    }
    $logger->debug("Book does not appear to be duplicate");
    return 0;
}

sub emit
{
    my %plash = @_;
    my @cmd = qw(calibredb add);
    unless (exists $plash{'file'})
    {
	$logger->warn("Book without corresponding file");
	return 0;	    
    }
    #if (lc(substr($plash{'file'}, -5)) ne '.epub')
    #{
	#$logger->debug("Only interested in epubs for this run");
	#return 0;
    #}
    # Don't flood out the Calibre content server
    select(undef, undef, undef, 0.05);
    if (isdup(%plash))
    {
	$logger->debug("Appears to be duplicate");
	return 0;
    }
    while (my ($k, $v) = each %plash)
    {
	if (substr($k, 0, 1) eq '-')
	{
	    push @cmd, $k, $v;
	}
    }
    push @cmd, $plash{'file'};
    if (exists $plash{'--authors'})
    {
	$logger->info("Authors: ", $plash{'--authors'});
	print("echo Authors: ", shell_quote($plash{'--authors'}), "\n");
    }
    if (exists $plash{'--title'})
    {
	$logger->info("Title: ", $plash{'--title'});
	print("echo Title: ", shell_quote($plash{'--title'}), "\n");	
    }
    $logger->info("Filename: ", $plash{'file'});
    print("echo Filename: ", shell_quote($plash{'file'}), "\n");
    print(shell_quote(@cmd), "\n");
    #system(@cmd);
    #system('true');
    if (($? == -1) || ($? & 127) || ($? >> 8))
    {
    	return 0;
    }
    return 1;
}

my $homedir = bsd_glob("~", GLOB_TILDE);
my $plistfile = File::Spec->catfile(
    $homedir,
    qw(
	Library 
	Containers 
	com.apple.BKAgentService 
	Data 
	Documents 
	iBooks 
	Books 
	Books.plist
    )
    );
$logger->info("Reading books plist file $plistfile");
my $fh = IO::Pipe->new();
$fh->reader(qw(plutil -convert xml1 -o - --), $plistfile);
$logger->debug("deserializing");
my $plist = Mac::PropertyList::SAX::parse_plist(join("", $fh->getlines()));
$fh->close();
#print YAML::Dump($plist);
my $processed = 0;
my $added = 0;
for my $entry (@{$plist->{'Books'}->value})
{
    $logger->debug($entry->value);
    $processed++;    
    $added += emit(plash($entry->value));
}

$logger->info("Processed $processed, added $added");

__END__

curl http://localhost:8081/interface-data/books-init?library_id=Calibre_Library\&search=author:Elly
