package Plugins::RadioApplets::Settings;

# Einstellungsseite: Ort und Seitenwechsel der Wetter-Uhr, CalDAV-Kalender für die Termine

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
	return ($prefs, qw(place pageTime calUrl calUser calPass calDays));
}

sub handler {
	my ($class, $client, $params) = @_;
	# nach dem Speichern laufen Ortssuche und Abfrage erst los, der Status ist also der vorige
	$params->{placeStatus} = $params->{saveSettings} && defined $params->{pref_place} && $params->{pref_place} ne $prefs->get('place')
		? 'Wird gesucht … (Seite gleich neu laden)'
		: $prefs->get('placeStatus');
	$params->{calStatus} = Plugins::RadioApplets::Calendar::status();
	return $class->SUPER::handler($client, $params);
}

1;
