package Plugins::RadioApplets::Plugin;

# Bietet den Squeezebox Radios eigene Applets über den Applet-Installer an.
# Die Zips liegen in applets/, Titel und Versionen in applets/applets.txt
# (beides erzeugt tools/build.py). Die Liste wird bei jeder
# Abfrage neu gelesen, neue Versionen brauchen also keinen LMS-Neustart.

use strict;
use base qw(Slim::Plugin::Base);

use Digest::SHA qw(sha1_hex);
use File::Spec::Functions qw(catdir catfile);

use Slim::Utils::Log;

my $log = Slim::Utils::Log->addLogCategory({
	category     => 'plugin.radioapplets',
	defaultLevel => 'WARN',
	description  => 'PLUGIN_RADIOAPPLETS',
});

my $dir;

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);

	$dir = catdir($class->_pluginDataFor('basedir'), 'applets');

	Slim::Control::Jive::registerExtensionProvider('RadioApplets', \&_provider);
	Slim::Web::Pages->addRawFunction('radioapplets/', \&_serveZip);
}

sub _readList {
	my @list;
	open(my $fh, '<:encoding(UTF-8)', catfile($dir, 'applets.txt')) or return ();
	while (my $line = <$fh>) {
		chomp $line;
		next if $line =~ /^\s*(#|$)/;
		my ($name, $version, $target, $file, $title, $desc) = split /\t/, $line;
		push @list, { name => $name, version => $version, target => $target,
			file => $file, title => $title, desc => $desc };
	}
	close $fh;
	return @list;
}

sub _provider {
	my $args = shift;
	my @res;

	if ($args->{type} eq 'applet') {
		for my $a (_readList()) {
			next if $args->{target} && $a->{target} && $args->{target} !~ /^(?:$a->{target})$/;
			my $path = catfile($dir, $a->{file});
			open(my $fh, '<:raw', $path) or next;
			my $data = do { local $/; <$fh> };
			close $fh;
			push @res, {
				name    => $a->{name},
				version => $a->{version},
				title   => $a->{title},
				desc    => $a->{desc},
				creator => 'Goetz Jacob',
				relurl  => "/radioapplets/$a->{file}",
				sha     => sha1_hex($data),
			};
		}
	}

	$args->{cb}->(@{$args->{pt}}, \@res);
}

sub _serveZip {
	my ($httpClient, $response) = @_;

	my ($file) = $response->request->uri->path =~ m{/radioapplets/([\w.-]+\.zip)$};
	my $data;
	if ($file && open(my $fh, '<:raw', catfile($dir, $file))) {
		$data = do { local $/; <$fh> };
		close $fh;
	}

	if (defined $data) {
		$response->code(200);
		$response->content_type('application/zip');
	} else {
		$log->warn('Applet nicht gefunden: ' . $response->request->uri->path);
		$data = 'not found';
		$response->code(404);
		$response->content_type('text/plain');
	}
	$response->header('Content-Length' => length($data));
	$response->header('Connection' => 'close');
	Slim::Web::HTTP::addHTTPResponse($httpClient, $response, \$data);
}

1;
