# AdronTec Scripts

> Bash-Automatisierungsscripts für Debian/Ubuntu-Server  
> by M.Tuppek · AdronTec IT Services

---

## Scripts

| Script | Beschreibung |
|--------|--------------|
| `de_system_setup.sh` | Deutsche Sprache, Zeitzone, Tastatur, nano & mc |
| `dockerm.sh` | Docker Manager – Installation, Container, Compose, Volumes, Update |

---

## Installation

### Deutsches System-Setup

```bash
# wget
wget -qO /tmp/de_system_setup.sh \
  https://raw.githubusercontent.com/halonke/snippet/main/scripts/de_system_setup.sh \
  && sudo bash /tmp/de_system_setup.sh

# curl
curl -fsSL \
  https://raw.githubusercontent.com/halonke/snippet/main/scripts/de_system_setup.sh \
  | sudo bash
```

**Kompatibel mit:** Debian 11/12/13 · Ubuntu 20.04–25.10 · Proxmox VE · Raspberry Pi OS

---

### Docker Manager (`dockerm`)

```bash
# wget – einmalige Installation (installiert sich selbst als 'dockerm')
wget -qO /tmp/dockerm.sh \
  https://raw.githubusercontent.com/halonke/snippet/main/scripts/dockerm.sh \
  && sudo bash /tmp/dockerm.sh

# curl
curl -fsSL \
  https://raw.githubusercontent.com/halonke/snippet/main/scripts/dockerm.sh \
  | sudo bash
```

Nach der ersten Ausführung steht `dockerm` systemweit zur Verfügung:

```bash
sudo dockerm                    # Menü starten
sudo dockerm --install-docker   # Nur Docker installieren
sudo dockerm --update-self      # dockerm aktualisieren
```

**Kompatibel mit:** Debian 12/13 · Ubuntu 22.04–25.10 · Docker CE v20+

---

## Updates

```bash
# Über Menüpunkt 41 (dockerm aktualisieren)
sudo dockerm  →  41

# Oder direkt per wget
wget -qO /usr/local/bin/dockerm \
  https://raw.githubusercontent.com/halonke/snippet/main/scripts/dockerm.sh \
  && chmod +x /usr/local/bin/dockerm

# Oder per curl
curl -fsSL \
  https://raw.githubusercontent.com/halonke/snippet/main/scripts/dockerm.sh \
  -o /usr/local/bin/dockerm && chmod +x /usr/local/bin/dockerm
```

---

## Docker Manager – Menüübersicht

```
 CONTAINER                    IMAGES
  1) Alle anzeigen            14) Anzeigen
  2) Laufende                 15) Pullen
  3) Starten                  16) Entfernen
  4) Stoppen                  17) Scout-Scan
  5) Neu starten              18) Ungenutzte löschen
  6) Entfernen
  7) Logs                     NETZWERK
  8) Shell/Exec               20) Anzeigen
  9) Inspect                  21) Erstellen
 10) Top                      22) Entfernen
 11) Stats (Live)             23) Inspizieren
 12) Healthchecks
 13) Export                   VOLUMES
                              24) Anzeigen
 SYSTEM & WARTUNG             25) Erstellen
 30) Compose Menü             26) Entfernen
 31) System Prune             27) Prune
 32) Speichernutzung          28) Backup
 33) Logging konfig.
 34) Docker Update            SETUP
 35) Docker Info              40) Docker installieren
 36) User → Gruppe            41) dockerm updaten (GitHub)
                              42) Info neu laden
```
