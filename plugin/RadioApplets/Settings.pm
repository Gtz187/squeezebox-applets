package Plugins::RadioApplets::Settings;

# Einstellungsseite: CalDAV-Kalender für die Termine auf der Wetter-Uhr

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.radioapplets');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_RADIOAPPLETS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/RadioApplets/settings/basic.html');
}

sub prefs {
	return ($prefs, qw(calUrl calUser calPass));
}

sub handler {
	my ($class, $client, $params) = @_;
	# nach dem Speichern läuft die Abfrage erst los, der Status ist also der vorige
	$params->{calStatus} = Plugins::RadioApplets::Calendar::status();
	return $class->SUPER::handler($client, $params);
}

1;
