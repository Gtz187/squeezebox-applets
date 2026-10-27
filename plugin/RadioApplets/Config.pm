package Plugins::RadioApplets::Config;

# Einstellungen für die Wetter-Uhr, die der LMS vorgibt (Ort, Seitenwechsel).
# Das Radio holt sie zusammen mit den Terminen aus /radioapplets/termine.json.
# Den Ort sucht der LMS bei Open-Meteo; geändert wird er auf dem Radio nur,
# wenn er hier neu gesetzt wurde (placeStamp), so bleibt „Ort ändern“
# am Radio weiter möglich.

use strict;

use JSON::XS;
use URI::Escape qw(uri_escape_utf8);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.radioapplets');
my $log   = logger('plugin.radioapplets');

sub init {
	$prefs->init({
		place       => '',
		placeName   => '',
		placeLat    => '',
		placeLon    => '',
		placeStamp  => 0,
		placeStatus => '',
		pageTime    => 8,
	});
	$prefs->setValidate({ validator => 'intlimit', low => 0, high => 600 }, 'pageTime');
	$prefs->setChange(\&_lookup, 'place');
}

# für das Radio
sub config {
	my $c = { pageTime => $prefs->get('pageTime') + 0 };
	if ($prefs->get('placeName') ne '') {
		$c->{place} = {
			name  => $prefs->get('placeName'),
			lat   => $prefs->get('placeLat') + 0,
			lon   => $prefs->get('placeLon') + 0,
			stamp => $prefs->get('placeStamp') + 0,
		};
	}
	return $c;
}

sub _setPlace {
	my ($name, $lat, $lon, $status) = @_;
	$prefs->set(placeName => $name);
	$prefs->set(placeLat => $lat);
	$prefs->set(placeLon => $lon);
	$prefs->set(placeStamp => time());
	$prefs->set(placeStatus => $status);
}

sub _lookup {
	my (undef, $query) = @_;
	$query =~ s/^\s+|\s+$//g;

	if ($query eq '') {
		_setPlace('', '', '', '');
		return;
	}

	# "50.8197, 12.5446" = Koordinaten direkt
	if (my ($lat, $lon) = $query =~ /^(-?\d{1,2}(?:\.\d+)?)\s*[,;\s]\s*(-?\d{1,3}(?:\.\d+)?)$/) {
		_setPlace("$lat, $lon", $lat, $lon, "Koordinaten $lat, $lon");
		return;
	}

	$prefs->set(placeStatus => "Suche „$query“ …");
	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $http = shift;
			my $obj = eval { decode_json($http->content) };
			my $r = $obj && ref $obj->{results} eq 'ARRAY' && $obj->{results}[0];
			if (!$r || !defined $r->{latitude}) {
				$prefs->set(placeStatus => "„$query“ nicht gefunden");
				return;
			}
			my @extra = grep { defined && $_ ne '' && $_ ne $r->{name} } $r->{admin1}, $r->{country};
			my $label = $r->{name} . (@extra ? ' (' . join(', ', @extra) . ')' : '');
			_setPlace($r->{name}, $r->{latitude}, $r->{longitude},
				sprintf('%s – %.4f, %.4f', $label, $r->{latitude}, $r->{longitude}));
		},
		sub {
			my ($http, $error) = @_;
			$prefs->set(placeStatus => "Ortssuche fehlgeschlagen: $error");
			$log->warn("Ortssuche: $error");
		},
		{ timeout => 15 },
	)->get('http://geocoding-api.open-meteo.com/v1/search?count=1&language=de&format=json&name=' . uri_escape_utf8($query));
}

1;
