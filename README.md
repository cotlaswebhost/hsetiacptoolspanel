# HestiaCP -> OLSPanel Restore Addon

This repository packages a production-tested enhancement for OLSPanel backup restore.

It adds support for restoring **HestiaCP backups** into OLSPanel with:

- Hestia backup format option in restore UI
- Flexible Hestia scope restore mode
- Web files restore from `domain_data.tar.zst`
- Database restore for `.sql`, `.sql.gz`, and `.sql.zst`
- WordPress DB credential sync in `wp-config.php`
- WordPress URL updates by restored database/domain map
- SSL restore from backup cert material
- Account metadata import from `hestia/user.conf`:
  - `NAME` -> first/last name
  - `CONTACT` -> email
  - `PACKAGE` -> package by name match (fallback to Unlimited/default)

## What This Changes

The installer replaces these files in OLSPanel:

- `users/database.py`
- `whm/views.py`
- `whm/templates/whm/backup_restore.html`

A timestamped backup is created before any replacement.

## Requirements

- Root access on target server
- Existing OLSPanel installation at `/usr/local/olspanel/mypanel`
- `python3`, `systemctl`, `curl`
- Optional but expected in your environment: `/root/venv/bin/python`

## Installation

### 1) Clone repository on target OLSPanel server

```bash
git clone git@github.com:cotlaswebhost/hsetiacptoolspanel.git
cd hsetiacptoolspanel
```

If you prefer HTTPS:

```bash
git clone https://github.com/cotlaswebhost/hsetiacptoolspanel.git
cd hsetiacptoolspanel
```

### 2) Run installer

```bash
chmod +x install.sh
./install.sh
```

You can also make both scripts executable at once:

```bash
chmod +x install.sh uninstall.sh
```

The installer will:

1. Verify required files and paths
2. Backup current OLSPanel target files
3. Deploy patched files
4. Run compile + Django checks
5. Restart `cp` service
6. Run panel health checks on `127.0.0.1:8001` and `:2083/login`

## Rollback

Installer prints the exact backup path after completion.

Example rollback:

```bash
cp -a /root/hsetiacptoolspanel-backups/<timestamp>/users/database.py /usr/local/olspanel/mypanel/users/database.py
cp -a /root/hsetiacptoolspanel-backups/<timestamp>/whm/views.py /usr/local/olspanel/mypanel/whm/views.py
cp -a /root/hsetiacptoolspanel-backups/<timestamp>/whm/templates/whm/backup_restore.html /usr/local/olspanel/mypanel/whm/templates/whm/backup_restore.html
systemctl restart cp
```

## Uninstall Addon

Use the uninstall script to restore original OLSPanel files from installer backups.

List available backups:

```bash
./uninstall.sh --list
```

Uninstall using latest backup (default behavior):

```bash
./uninstall.sh
```

Uninstall using a specific backup directory:

```bash
./uninstall.sh --backup-dir /root/hsetiacptoolspanel-backups/<timestamp>
```

The uninstall script will:

1. Restore target files from chosen backup
2. Run compile + Django checks
3. Restart `cp` and run health checks
4. Save your current (pre-uninstall) files into `/root/hsetiacptoolspanel-uninstall-backups/<timestamp>`

## Reinstall Test Cycle

To test uninstall/install repeatedly:

```bash
cd /root/hsetiacptoolspanel
./uninstall.sh
./install.sh
```

## Usage After Install

In OLSPanel backup restore page:

1. Select `HestiaCP` format.
2. Choose source (`upload`, `url`, local, or ftp as supported by your panel flow).
3. Select Hestia scope (`per_domain` recommended for multi-domain backups).
4. Start restore.

## Notes

- This repo is an addon/overlay for existing OLSPanel installs.
- It is designed for repeated use across VPS/dedicated instances with similar OLSPanel layout.
- Always test first on staging before broad rollout.
