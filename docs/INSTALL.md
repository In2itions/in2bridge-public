# Install in2bridge

This document describes the intended public installation flow.

## Ubuntu/Debian

If this node will also host the in2bridge database, run the database setup
first:

```bash
sudo ./install/setup-database.sh
```

The database setup script installs MariaDB, asks for database name, user, and
password, then creates the database and grants.

Install the application:

```bash
sudo ./install/install-in2bridge.sh
```

The installer will:

1. Install required OS client tools.
2. Install the in2bridge runtime package.
3. Install the in2bridge engine package.
4. Ask for database host, name, user, and password.
5. Test the database connection.
6. Run the in2bridge schema migrations.
7. Write `/etc/in2bridge/in2bridge.env`.
8. Enable and start `in2bridge-engine.service`.

To reconfigure database access later:

```bash
sudo /opt/in2bridge/install/configure-app-database.sh
```

For test nodes, remove the application and optionally drop the test database:

```bash
sudo /opt/in2bridge/install/cleanup-in2bridge.sh --drop-database
```

## Runtime policy

The installer must use in2bridge-provided FFmpeg, SRT, and RIST runtime files
under `/opt/in2bridge/runtime`. Distro versions are not used for transport or
preview behavior.

## License

Customer packages do not include a license generator. Offline licenses are
generated internally and imported through the management UI or API.
