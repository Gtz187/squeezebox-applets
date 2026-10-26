package Plugins::RadioApplets::Calendar;

# Holt die nächsten Termine aus einem CalDAV-Kalender (Baïkal, Nextcloud, …)
# und hält sie für /radioapplets/termine.json bereit. Abgefragt wird per
# REPORT mit <expand>, so löst der Server Serientermine selbst auf.
# Adresse und Zugangsdaten stehen nur in den LMS-Einstellungen des Plugins.

use strict;

use Digest::MD5 qw(md5_hex);
use Encode qw(decode);
use JSON::XS;
use MIME::Base64 qw(encode_base64);
use POSIX qw(strftime);
use Time::Local qw(timegm timelocal);
use URI;

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

use constant REFRESH => 15 * 60;   # Sekunden
use constant DAYS    => 60;        # so weit voraus wird gesucht
use constant MAX     => 10;        # so viele Termine bekommt das Radio

my $prefs = preferences('plugin.radioapplets');
my $log   = logger('plugin.radioapplets');

my $events  = [];
my $status  = '';
my $fetched = 0;

sub init {
	$prefs->init({ calUrl => '', calUser => '', calPass => '' });
	$prefs->setChange(\&refresh, qw(calUrl calUser calPass));
	refresh();
}

sub status { $status }

sub json {
	return JSON::XS->new->utf8->canonical->encode({
		status  => $status,
		fetched => $fetched,
		events  => $events,
	});
}

sub refresh {
	Slim::Utils::Timers::killTimers(undef, \&refresh);
	Slim::Utils::Timers::setTimer(undef, time() + REFRESH, \&refresh);

	my $url = $prefs->get('calUrl');
	if (!$url) {
		$events = [];
		$status = 'Kein Kalender eingestellt';
		return;
	}

	# erst ohne Anmeldung anfragen: die 401-Antwort nennt das Verfahren
	# (Basic oder Digest) und bei Digest die Nonce
	Slim::Networking::SimpleAsyncHTTP->new(
		sub { _report($url) },
		sub {
			my ($http, $error, $res) = @_;
			my $challenge = $res && $res->code == 401 && $res->header('WWW-Authenticate');
			$challenge ? _report($url, $challenge) : _fail("Kalender nicht erreichbar: $error");
		},
		{ timeout => 20 },
	)->get($url);
}

sub _report {
	my ($url, $challenge) = @_;

	my $now = time();
	my $range = sprintf('start="%s" end="%s"', _utc($now), _utc($now + DAYS * 86400));
	my $body = <<"EOF";
<?xml version="1.0" encoding="utf-8"?>
<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
 <D:prop><C:calendar-data><C:expand $range/></C:calendar-data></D:prop>
 <C:filter><C:comp-filter name="VCALENDAR"><C:comp-filter name="VEVENT">
  <C:time-range $range/>
 </C:comp-filter></C:comp-filter></C:filter>
</C:calendar-query>
EOF

	my @headers = (Depth => 1, 'Content-Type' => 'application/xml; charset=utf-8');
	push @headers, Authorization => _auth('REPORT', $url, $challenge) if $challenge;

	Slim::Networking::SimpleAsyncHTTP->new(
		\&_parse,
		sub {
			my ($http, $error, $res) = @_;
			_fail($res && $res->code == 401 ? 'Anmeldung abgelehnt (Benutzer/Passwort?)' : "Abfrage fehlgeschlagen: $error");
		},
		{ timeout => 30 },
	)->_createHTTPRequest(REPORT => $url, @headers, $body);
}

sub _auth {
	my ($method, $url, $challenge) = @_;
	my ($user, $pass) = ($prefs->get('calUser'), $prefs->get('calPass'));

	return 'Basic ' . encode_base64("$user:$pass", '') if $challenge =~ /^\s*Basic/i;

	my %p;
	while ($challenge =~ /(\w+)=(?:"([^"]*)"|([^\s,]*))/g) {
		$p{lc $1} = defined $2 ? $2 : $3;
	}
	my $uri    = URI->new($url)->path_query;
	my $ha1    = md5_hex("$user:$p{realm}:$pass");
	my $ha2    = md5_hex("$method:$uri");
	my $cnonce = sprintf('%08x%08x', int(rand(2**32)), int(rand(2**32)));
	my $qop    = defined $p{qop} && $p{qop} =~ /\bauth\b/;

	my $h = qq{Digest username="$user", realm="$p{realm}", nonce="$p{nonce}", uri="$uri", response="}
		. ($qop ? md5_hex("$ha1:$p{nonce}:00000001:$cnonce:auth:$ha2") : md5_hex("$ha1:$p{nonce}:$ha2")) . '"';
	$h .= qq{, qop=auth, nc=00000001, cnonce="$cnonce"} if $qop;
	$h .= qq{, opaque="$p{opaque}"} if defined $p{opaque};
	$h .= qq{, algorithm=$p{algorithm}} if $p{algorithm};
	return $h;
}

sub _parse {
	my $http = shift;
	my $xml = eval { decode('UTF-8', $http->content) } // $http->content;

	my @list;
	while ($xml =~ m{<[\w:-]*calendar-data[^>]*>(.*?)</[\w:-]*calendar-data>}gs) {
		my $ics = _unxml($1);
		$ics =~ s/\r?\n[ \t]//g;   # gefaltete Zeilen zusammenfügen
		while ($ics =~ /BEGIN:VEVENT(.*?)END:VEVENT/gs) {
			my $e = _event($1);
			push @list, $e if $e;
		}
	}

	my $now = time();
	@list = sort { $a->{start} <=> $b->{start} || $a->{title} cmp $b->{title} } grep { $_->{ende} > $now } @list;
	splice @list, MAX if @list > MAX;

	$events  = \@list;
	$fetched = $now;
	$status  = sprintf('%d Termine geladen (%s)', scalar @list, strftime('%d.%m. %H:%M', localtime $now));
	main::INFOLOG && $log->info($status);
}

sub _event {
	my %f;
	for my $line (split /\r?\n/, shift) {
		my ($name, $params, $value) = $line =~ /^([A-Z-]+)((?:;[^:]*)?):(.*)$/ or next;
		$f{$name} ||= [$params, $value];
	}
	return if !$f{DTSTART} || ($f{STATUS} && $f{STATUS}[1] =~ /CANCELLED/i);

	my ($start, $allday) = _time($f{DTSTART}[1]);
	return unless defined $start;

	my $ende;
	if ($f{DTEND}) {
		($ende) = _time($f{DTEND}[1]);
	} elsif ($f{DURATION} && $f{DURATION}[1] =~ /^P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/) {
		$ende = $start + ((($1 || 0) * 7 + ($2 || 0)) * 24 + ($3 || 0)) * 3600 + ($4 || 0) * 60 + ($5 || 0);
	}
	$ende ||= $allday ? $start + 86400 : $start;

	my $title = $f{SUMMARY} ? $f{SUMMARY}[1] : '';
	$title =~ s/\\n/ /gi;
	$title =~ s/\\([,;\\])/$1/g;

	return { start => $start, ende => $ende, allday => $allday ? JSON::XS::true : JSON::XS::false, title => $title };
}

# "20261026" (ganztägig, Mitternacht Ortszeit), "20261027T073000Z" (UTC),
# "20261027T093000" (Ortszeit des Servers)
sub _time {
	my $v = shift;
	if (my ($y, $m, $d) = $v =~ /^(\d{4})(\d\d)(\d\d)$/) {
		return (timelocal(0, 0, 0, $d, $m - 1, $y), 1);
	}
	if (my ($y, $m, $d, $H, $M, $S, $z) = $v =~ /^(\d{4})(\d\d)(\d\d)T(\d\d)(\d\d)(\d\d)(Z?)$/) {
		return ($z ? timegm($S, $M, $H, $d, $m - 1, $y) : timelocal($S, $M, $H, $d, $m - 1, $y), 0);
	}
	return;
}

sub _utc { strftime('%Y%m%dT%H%M%SZ', gmtime shift) }

sub _unxml {
	my $s = shift;
	$s =~ s/^\s*<!\[CDATA\[(.*)\]\]>\s*$/$1/s and return $s;
	$s =~ s/&lt;/</g;
	$s =~ s/&gt;/>/g;
	$s =~ s/&quot;/"/g;
	$s =~ s/&apos;/'/g;
	$s =~ s/&#x([0-9a-f]+);/chr(hex $1)/gie;
	$s =~ s/&#(\d+);/chr($1)/ge;
	$s =~ s/&amp;/&/g;
	return $s;
}

sub _fail {
	$status = shift;
	$log->warn($status);
}

1;
