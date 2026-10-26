#!/usr/bin/env python3
"""Baut Applet-Zips, das LMS-Plugin und die Repository-Datei repo.xml.

Aufruf: python3 tools/build.py [--deploy SSH-ZIEL:PLUGIN-ORDNER]
  - applets/<Name>         -> plugin/RadioApplets/applets/<Name>-<Version>.zip + applets.txt
  - plugin/RadioApplets    -> dist/RadioApplets-<Version>.zip
  - repo.xml               -> verweist auf dist/RadioApplets-<Version>.zip (mit SHA1)
  - --deploy kopiert das Plugin zusätzlich direkt in einen LMS (zum Testen ohne GitHub),
    z. B. --deploy unraid:/mnt/user/appdata/LyrionMusicServer/cache/InstalledPlugins/Plugins

Nach jeder Änderung an einem Applet dessen Version hochzählen, sonst bieten die
Radios kein Update an. Und PLUGIN_VERSION hochzählen, sonst bietet der LMS kein
Plugin-Update an.
"""
import hashlib, os, re, subprocess, sys, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLUGIN = os.path.join(ROOT, "plugin", "RadioApplets")
APPLET_OUT = os.path.join(PLUGIN, "applets")
DIST = os.path.join(ROOT, "dist")
DATE = (2026, 1, 1, 0, 0, 0)

# Wo repo.xml und die Plugin-Zips im Netz liegen (raw-Ansicht des GitHub-Repos)
REPO_URL = "https://github.com/Gtz187/squeezebox-applets"
RAW_URL = "https://raw.githubusercontent.com/Gtz187/squeezebox-applets/main"

PLUGIN_VERSION = "1.5"

APPLETS = [
	# name, version, target (Regex auf System:getMachine()), Titel, Beschreibung
	("Wetter", "1.4", "baby", "Wetter-Uhr",
	 "Wetter (Open-Meteo) für einen wählbaren Ort als Menüpunkt und Bildschirmschoner, mit Sender/Titel, Eieruhr-Restzeit und den nächsten Terminen."),
	("Eieruhr", "1.1", "baby", "Eieruhr",
	 "Küchentimer: Zeit per Rad einstellen, Piepton und „Fertig!“ am Ende."),
]


def zip_dir(src, out):
	dirs, files = [], []
	for root, dnames, fnames in os.walk(src):
		dnames.sort()
		rel = os.path.relpath(root, src)
		if rel != ".":
			dirs.append(rel + "/")
		files += [os.path.join(rel, f) if rel != "." else f for f in sorted(fnames)]
	with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
		# Ordner zuerst: der Applet-Installer des Radios legt sie nur an, wenn ihr
		# Eintrag vor den Dateien kommt, und stolpert, wenn der letzte Eintrag ein Ordner ist
		# feste Zeitstempel: gleicher Inhalt ergibt gleiche Zip und gleiche SHA1
		# und Unix-Rechte setzen: ohne sie legt Archive::Zip im LMS die Ordner mit
		# 0600 an und kann danach nichts hineinentpacken
		for d in dirs:
			info = zipfile.ZipInfo(d, DATE)
			info.external_attr = (0o40755 << 16) | 0x10
			z.writestr(info, "")
		for f in files:
			info = zipfile.ZipInfo(f, DATE)
			info.external_attr = 0o100644 << 16
			info.compress_type = zipfile.ZIP_DEFLATED
			with open(os.path.join(src, f), "rb") as fh:
				z.writestr(info, fh.read())


def sha1(path):
	with open(path, "rb") as fh:
		return hashlib.sha1(fh.read()).hexdigest()


def xml(s):
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def build_applets():
	os.makedirs(APPLET_OUT, exist_ok=True)
	for f in os.listdir(APPLET_OUT):
		os.remove(os.path.join(APPLET_OUT, f))
	lines = []
	for name, version, target, title, desc in APPLETS:
		zname = f"{name}-{version}.zip"
		zip_dir(os.path.join(ROOT, "applets", name), os.path.join(APPLET_OUT, zname))
		lines.append("\t".join((name, version, target, zname, title, desc)))
		print("Applet", name, version)
	with open(os.path.join(APPLET_OUT, "applets.txt"), "w", encoding="utf-8") as fh:
		fh.write("# name\tversion\ttarget\tzip\ttitel\tbeschreibung\n" + "\n".join(lines) + "\n")


def build_plugin():
	path = os.path.join(PLUGIN, "install.xml")
	with open(path, encoding="utf-8") as fh:
		s = fh.read()
	s = re.sub(r"<version>[^<]*</version>", f"<version>{PLUGIN_VERSION}</version>", s)
	with open(path, "w", encoding="utf-8") as fh:
		fh.write(s)

	os.makedirs(DIST, exist_ok=True)
	out = os.path.join(DIST, f"RadioApplets-{PLUGIN_VERSION}.zip")
	zip_dir(PLUGIN, out)
	print("Plugin", PLUGIN_VERSION, sha1(out))
	return out


def write_repo(zip_path):
	changes = "\n".join(f"{title} {version}" for _, version, _, title, _ in APPLETS)
	s = f"""<?xml version="1.0" encoding="utf-8"?>
<!-- erzeugt von tools/build.py, nicht von Hand bearbeiten -->
<extensions>
	<details>
		<title lang="DE">Squeezebox-Radio-Applets</title>
		<title lang="EN">Squeezebox Radio applets</title>
	</details>
	<plugins>
		<plugin name="RadioApplets" version="{PLUGIN_VERSION}" minTarget="8.0" maxTarget="*">
			<title lang="DE">Radio-Applets (Wetter-Uhr, Eieruhr)</title>
			<title lang="EN">Radio applets (weather clock, kitchen timer)</title>
			<desc lang="DE">Bietet Squeezebox Radios die Applets Wetter-Uhr und Eieruhr über den Applet-Installer an (Einstellungen → Erweitert → Applet-Installer). Die Wetter-Uhr zeigt auf Wunsch die nächsten Termine aus einem CalDAV-Kalender.</desc>
			<desc lang="EN">Offers the applets weather clock and kitchen timer to Squeezebox Radios via the applet installer (Settings → Advanced → Applet Installer). The weather clock can show upcoming events from a CalDAV calendar. German UI.</desc>
			<changes lang="DE">{xml(changes)}</changes>
			<creator>Götz Jacob</creator>
			<category>hardware</category>
			<link>{REPO_URL}</link>
			<url>{RAW_URL}/dist/{os.path.basename(zip_path)}</url>
			<sha>{sha1(zip_path)}</sha>
		</plugin>
	</plugins>
</extensions>
"""
	with open(os.path.join(ROOT, "repo.xml"), "w", encoding="utf-8") as fh:
		fh.write(s)


def main():
	build_applets()
	zip_path = build_plugin()
	write_repo(zip_path)

	if "--deploy" in sys.argv:
		host, _, lms_dir = sys.argv[sys.argv.index("--deploy") + 1].partition(":")
		tar = subprocess.run(["tar", "cf", "-", "-C", os.path.dirname(PLUGIN), "RadioApplets"],
			capture_output=True, check=True).stdout
		# eigene SSH-Konfiguration über SSH_CONFIG, z. B. SSH_CONFIG=~/.ssh/lms_config
		ssh = ["ssh"] + (["-F", os.environ["SSH_CONFIG"]] if os.environ.get("SSH_CONFIG") else [])
		subprocess.run(ssh + [host,
			f"rm -rf {lms_dir}/RadioApplets && tar xf - -C {lms_dir} && chown -R nobody:users {lms_dir}/RadioApplets"],
			input=tar, check=True)
		print("deployed")


main()
